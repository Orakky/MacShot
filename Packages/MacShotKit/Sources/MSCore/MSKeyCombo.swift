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
