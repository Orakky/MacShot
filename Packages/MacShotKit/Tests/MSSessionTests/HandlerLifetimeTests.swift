import Foundation
import Testing
import MSCore
@testable import MSHotKey

/// 用户 11-19 报的"⌃⌘N 注册成功但按了没反应"。双通道实测：系统事件流里 10 次
/// `keyCode=45 mods=⌘⌃`，MacShot 自家日志 0 条派发记录 ⇒ 事件进得来、我们的回调没跑。
/// 根因＝`register()` 里先 `setHandler` 再 `unregister`，而 `unregister` 会擦**静态共享**的回调表。
///
/// 两条注意：① 回调表是进程级静态的 ⇒ 本套件必须 `.serialized`，并行跑会互相把对方的 handler 擦掉
/// （第一版就是这么红的，红得毫无意义）；② `dispatch` 用 `DispatchQueue.main.async` 跳主线程，
/// 所以断言前必须让主队列排空一次，否则测的是"还没跑"而不是"没挂上"。
@Suite(.serialized)
struct HandlerLifetimeTests {
    /// 几乎不可能撞车的组合；每条测试自己收尾，不留全局热键。
    private static let comboA = MSKeyCombo(keyCode: 1, command: true, option: true, control: true, shift: true)
    private static let comboB = MSKeyCombo(keyCode: 2, command: true, option: true, control: true, shift: true)

    @MainActor
    @Test("register 之后回调必须还在（否则 Carbon 派发到 dispatch 时静默丢弃）")
    func handlerSurvivesRegister() async throws {
        let service = CarbonHotKeyService()
        service.unregisterAll()
        var fired = false
        let result = service.register(Self.comboA, id: .snip) { fired = true }
        if case .ok = result { } else { Issue.record("注册本身就失败了，这条测试问不到点上：\(result)") }

        CarbonHotKeyService.dispatch(id: MSHotKeyID.snip.rawValue)     // 模拟 Carbon 回调进来了
        try await Task.sleep(for: .milliseconds(60))                   // 等主队列把 async 块排空
        service.unregisterAll()
        #expect(fired, "register 之后回调表里没有这个 id ⇒ 热键注册成功但永远不会有任何动作")
    }

    @MainActor
    @Test("改绑之后旧回调彻底让位；unregisterAll 之后不该还有回调活着")
    func rebindReplacesTheHandler() async throws {
        let service = CarbonHotKeyService()
        service.unregisterAll()
        var oldFired = 0, newFired = 0
        _ = service.register(Self.comboA, id: .snip) { oldFired += 1 }
        _ = service.register(Self.comboB, id: .snip) { newFired += 1 }

        CarbonHotKeyService.dispatch(id: MSHotKeyID.snip.rawValue)
        try await Task.sleep(for: .milliseconds(60))
        #expect(newFired == 1 && oldFired == 0, "改绑后旧回调还在跑或新回调没接上：old=\(oldFired) new=\(newFired)")

        service.unregisterAll()
        CarbonHotKeyService.dispatch(id: MSHotKeyID.snip.rawValue)
        try await Task.sleep(for: .milliseconds(60))
        #expect(oldFired == 0 && newFired == 1, "unregisterAll 之后不该还有回调活着：old=\(oldFired) new=\(newFired)")
    }
}
