import Foundation

/// A key combination in transportable form: lives in `MSCore` because settings stores it, the hot
/// key service consumes it, and the settings UI renders it — none of which may import Carbon.
public struct MSKeyCombo: Hashable, Sendable, Codable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(keyCode: UInt16, command: Bool = false, option: Bool = false,
                control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Function key with no modifiers — Snipaste-style defaults (`Q-02`).
    /// Takes the F-number (1…12), not the virtual key code: passing a code is what made F1
    /// silently register as "A" on 2026-11-16. Unknown numbers are reported, never guessed.
    public static func functionKey(_ number: Int) -> MSKeyCombo {
        guard let code = MSKeyCombo.functionKeyCodes[number] else {
            preconditionFailure("functionKey takes 1…12, got \(number) — use MSKeyCombo.f1 etc.")
        }
        return MSKeyCombo(keyCode: code)
    }

    public static let f1 = MSKeyCombo(keyCode: 122)
    public static let f2 = MSKeyCombo(keyCode: 120)
    public static let f3 = MSKeyCombo(keyCode: 99)
    public static let f4 = MSKeyCombo(keyCode: 118)

    /// Virtual key codes for F1…F12. Keeping them in one table is what makes the
    /// "no magic numbers in hot key code" gate checkable (`coding-conventions.md` §2).
    public static let functionKeyCodes: [Int: UInt16] = [
        1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98, 8: 100, 9: 101, 10: 109, 11: 103, 12: 111,
    ]

    public var requiresModifier: Bool { command || option || control || shift }

    /// Display form used by the settings UI and the menu (`⌥⌘W`, `F1`).
    public var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += MSKeyCombo.keyNames[keyCode] ?? "??"
        return s
    }

    public static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "'", 41: "K", 42: ";", 43: "\\", 45: "N", 46: "M", 47: ",", 48: "/", 49: ".",
        50: "`", 51: "Space", 53: "Esc", 36: "↩", 76: "↩", 122: "F1", 120: "F2",
        99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]
}

// MARK: - 可绑定性判定（纯函数，UI 只负责显示结果）

public extension MSKeyCombo {
    /// 系统保留/合成键：允许用户绑上去但要先警告——它们往往抢不过输入法、登录框或触摸板手势。
    static let riskyKeyCodes: Set<UInt16> = [53 /* Esc */, 49 /* Space */, 36 /* Return */, 76 /* keypad Enter */]

    enum Bindability: Equatable, Sendable {
        case ok
        case functionKeyNeedsHint          // 纯 F1…F12：合法，但 MacBook 上可能要按 fn
        case needsModifier                  // 既没有修饰键也不是功能键 → 会吃掉日常输入
        case reserved                       // Esc/Space 等
        case unsupported

        public var isBindable: Bool {
            switch self { case .ok, .functionKeyNeedsHint: return true; default: return false }
        }

        public var message: String? {
            switch self {
            case .ok: return nil
            case .functionKeyNeedsHint: return "F 键在部分键盘上需要同时按 fn；若无效请改用 ⌘/⌥ 组合"
            case .needsModifier: return "需要 ⌘、⌥ 或 ⌃ 之一（否则会和日常输入冲突）"
            case .reserved: return "这个键被系统或输入法占用风险高，换一个"
            case .unsupported: return "无法识别这个按键"
            }
        }
    }

    /// 判定规则集中在这一处，设置窗与热键服务共用（同一事实只有一个家）。
    static func bindability(keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool) -> Bindability {
        let hasModifier = command || option || control
        if riskyKeyCodes.contains(keyCode) { return .reserved }
        if functionKeyCodes.values.contains(keyCode) { return hasModifier ? .ok : .functionKeyNeedsHint }
        // keyCode 0 是 A 键，不是"未知"——写成 0 ⇒ 非法会让 ⌘A 这类常见组合被拒（11-16 自查抓出）。
        guard keyCode <= 127, keyNames[keyCode] != nil else { return .unsupported }
        return hasModifier ? .ok : .needsModifier
    }

    /// `shift` 只作为大小写呈现（⌘⇧A 与 ⌘A 是不同的注册项，所以 shift 参与判定但不计入"有修饰键"）。
    static func bindability(keyCode: UInt16, modifiers: Set<String>) -> Bindability {
        bindability(keyCode: keyCode,
                    command: modifiers.contains("command"),
                    option: modifiers.contains("option"),
                    control: modifiers.contains("control"),
                    shift: modifiers.contains("shift"))
    }
}
