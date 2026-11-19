import Carbon.HIToolbox
import Foundation
import MSCore

public enum MSHotKeyID: UInt32, Sendable, CaseIterable, Codable {
    case snip = 1, pinClipboard = 2, fullScreen = 3
}

public enum MSRegistrationResult: Sendable, Equatable {
    case ok
    case alreadyTaken(Int32)
    case failed(Int32)

    init(_ status: OSStatus) {
        // Measured 2026-11-16: a duplicate registration returns -9878 (eventHotKeyExistsErr).
        // Compared numerically because the published constant is typed Int while the API hands back OSStatus.
        switch status {
        case 0: self = .ok
        case Int32(exactly: Int(eventHotKeyExistsErr) ?? -9877): self = .alreadyTaken(status)
        default: self = .failed(status)
        }
    }
}

public protocol MSHotKeyServing: Sendable {
    @discardableResult
    func register(_ combo: MSKeyCombo, id: MSHotKeyID, handler: @escaping @Sendable () -> Void) -> MSRegistrationResult
    func unregister(_ id: MSHotKeyID)
    func unregisterAll()
    var conflicts: [MSHotKeyID] { get }
}

/// Global hot keys through Carbon (`ADR-010`): no extra TCC permission, and the callback does
/// nothing but hop to the main actor.
public final class CarbonHotKeyService: MSHotKeyServing, @unchecked Sendable {
    private static let signature = fourCC("MShk")
    private static let lock = NSLock()
    private static var handlers: [UInt32: @Sendable () -> Void] = [:]
    private static let sharedHandler: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr else { return status }
        CarbonHotKeyService.dispatch(id: hotKeyID.id)
        return noErr
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var taken: [MSHotKeyID] = []
    private var eventHandlerRef: EventHandlerRef?
    private let queue = DispatchQueue(label: "com.macshot.hotkey")

    public init() { installHandlerIfNeeded() }

    deinit {
        CarbonHotKeyService.forgetHandlers(ids: Array(refs.keys))
        refs.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    public var conflicts: [MSHotKeyID] { queue.sync { taken } }

    @discardableResult
    public func register(_ combo: MSKeyCombo, id: MSHotKeyID, handler: @escaping @Sendable () -> Void) -> MSRegistrationResult {
        installHandlerIfNeeded()
        // 顺序就是这次的 bug 本体：`unregister` 会 `forgetHandlers([id])`，而回调表是**静态共享**的。
        // 先 setHandler 再 unregister，等于把刚挂上去的那条擦掉 ⇒ Carbon 注册成功、事件也确实派发进来，
        // 但 `dispatch(id:)` 查不到回调就静默返回——用户看到的正是"注册成功却按了没反应"（`E-089`）。
        unregister(id)
        CarbonHotKeyService.setHandler(handler, for: id.rawValue)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, hotKeyID,
                                        GetApplicationEventTarget(), 0, &ref)
        let result = MSRegistrationResult(status)
        queue.sync {
            switch result {
            case .ok:
                if let ref { refs[id.rawValue] = ref }
                taken.removeAll { $0 == id }
                MSLog.info(.hotkey, "registered \(id.rawValue) = \(combo.display)")
            case .alreadyTaken(let code):
                taken.removeAll { $0 == id }; taken.append(id)
                MSLog.error(.hotkey, "conflict id=\(id.rawValue) combo=\(combo.display) OSStatus=\(code) ('evtalready')")
            case .failed(let code):
                taken.removeAll { $0 == id }; taken.append(id)
                MSLog.error(.hotkey, "register failed id=\(id.rawValue) OSStatus=\(code)")
            }
        }
        return result
    }

    public func unregister(_ id: MSHotKeyID) {
        var ref: EventHotKeyRef?
        queue.sync { ref = refs.removeValue(forKey: id.rawValue) }
        if let ref { UnregisterEventHotKey(ref) }
        CarbonHotKeyService.forgetHandlers(ids: [id.rawValue])
    }

    public func unregisterAll() {
        var all: [EventHotKeyRef] = []
        var ids: [UInt32] = []
        queue.sync { all = Array(refs.values); ids = Array(refs.keys); refs.removeAll(); taken.removeAll() }
        all.forEach { UnregisterEventHotKey($0) }
        // 与 `unregister(_:)` 对齐：拆了注册就把回调一起擦掉。少这一步会留下"注册已拆、回调还在表里"
        // 的不对称状态——真机上没人派发所以看不出来，但静态表里多一条永远不该被跑的闭包。
        CarbonHotKeyService.forgetHandlers(ids: ids)
    }

    /// Rebind with rollback: register the new set, and if any id fails, restore `previous`
    /// rather than leaving the user with a half-dead key map (`FR-HOT-002` judgement).
    @discardableResult
    public func rebind(to combos: [(MSHotKeyID, MSKeyCombo)],
                       previous: [(MSHotKeyID, MSKeyCombo)],
                       handlers: @escaping (MSHotKeyID) -> @Sendable () -> Void) -> [MSHotKeyID: MSRegistrationResult] {
        for (id, _) in combos { unregister(id) }
        var results: [MSHotKeyID: MSRegistrationResult] = [:]
        for (id, combo) in combos { results[id] = register(combo, id: id, handler: handlers(id)) }
        let failures = results.filter { if case .ok = $0.value { return false }; return true }.map(\.key)
        if !failures.isEmpty {
            MSLog.error(.hotkey, "rebind failed for \(failures.map(\.rawValue)) — rolling back previous set")
            for (id, combo) in previous { _ = register(combo, id: id, handler: handlers(id)) }
        }
        return results
    }

    private func installHandlerIfNeeded() {
        queue.sync {
            guard eventHandlerRef == nil else { return }
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), Self.sharedHandler, 1, &spec, nil, &eventHandlerRef)
        }
    }

    private static func setHandler(_ handler: @escaping @Sendable () -> Void, for id: UInt32) {
        lock.lock(); handlers[id] = handler; lock.unlock()
    }

    static func forgetHandlers(ids: [UInt32]) {
        lock.lock(); ids.forEach { handlers[$0] = nil }; lock.unlock()
    }

    /// internal：测试要能模拟"Carbon 回调进来了"，否则只能真按键盘，判据永远差一手。
    static func dispatch(id: UInt32) {
        lock.lock(); let handler = handlers[id]; lock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async(execute: handler)
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var out: UInt32 = 0
        for byte in s.utf8.prefix(4) { out = (out << 8) | UInt32(byte) }
        return out
    }
}

extension MSKeyCombo {
    /// Carbon modifier mask. Deliberately not `NSEvent.ModifierFlags`: the raw values differ.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if command { m |= UInt32(cmdKey) }
        if option { m |= UInt32(optionKey) }
        if control { m |= UInt32(controlKey) }
        if shift { m |= UInt32(shiftKey) }
        return m
    }
}
