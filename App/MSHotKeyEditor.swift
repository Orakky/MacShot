import AppKit
import MSCore
import MSHotKey
import MSSettings

/// 热键改绑控件（`design/screens.md#UI-005` 的热键组）。
///
/// 三条来自实测/规格的要求：
/// 1. 录制期间必须**先注销**该 id 的旧注册，否则新键会被自己吞掉（`hotkey-and-permissions.md` §3）。
/// 2. 注册失败要**回滚到旧组合**，不能留下"新旧都不响"的状态（`FR-HOT-002`）。
/// 3. 能不能绑由 `MSCore` 的纯函数判定，这里只负责显示结果（有单测）。
@MainActor
final class MSHotKeyEditor: NSObject, NSMenuDelegate {
    private struct Row {
        let id: MSHotKeyID
        let field: NSButton
    }

    private var rows: [Row] = []
    private var monitor: Any?
    private var recording: MSHotKeyID?
    private let hint = NSTextField(labelWithString: "　")

    /// 由 App 提供：写入偏好并重新注册，返回注册结果。
    var onCommit: ((MSHotKeyID, MSKeyCombo) -> MSRegistrationResult)?
    var onResetToDefaults: (() -> Void)?

    private(set) var stack = NSStackView()

    func build(prefs: MSAppPreferences) -> NSView {
        stack = NSStackView(views: [])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let specs: [(MSHotKeyID, String, MSKeyCombo)] = [
            (.snip, "截图", prefs.hotKeys.snip),
            (.pinClipboard, "贴出剪贴板图像", prefs.hotKeys.pinClipboard),
            (.fullScreen, "全屏截图", prefs.hotKeys.fullScreen),
        ]
        for (id, title, combo) in specs {
            let field = NSButton(title: combo.display, target: self, action: #selector(startRecording(_:)))
            field.bezelStyle = .rounded
            field.tag = Int(id.rawValue)
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
            field.toolTip = "点这里，然后按下新组合"
            rows.append(Row(id: id, field: field))
            stack.addArrangedSubview(row(label(title), field))
        }

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        stack.addArrangedSubview(hint)

        let restore = NSButton(title: "恢复默认热键", target: self, action: #selector(reset))
        restore.bezelStyle = .rounded
        stack.addArrangedSubview(restore)
        return stack
    }

    // MARK: - 录制

    @objc private func startRecording(_ sender: NSButton) {
        guard let row = rows.first(where: { $0.field.tag == sender.tag }) else { return }
        if recording == row.id { stopRecording(); return }
        stopRecording()
        recording = row.id
        originalCombo = comboFor(currentPrefs(), row.id)
        sender.title = "按下新键…"
        sender.contentTintColor = .controlAccentColor
        hint.stringValue = "正在录制 \(row.id.name)：按 Esc 取消。旧的注册已临时注销。"
        // 注销 → 新键才不会被旧注册吃掉（这一步漏掉的表现是"按了没反应"）
        unregister(row.id)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.consume(event)
        }
    }

    private func consume(_ event: NSEvent) -> NSEvent? {
        guard let id = recording else { return event }
        if event.type == .flagsChanged { return nil }          // 按住修饰键等待，不吃事件语义
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let combo = MSKeyCombo(keyCode: event.keyCode,
                               command: flags.contains(.command),
                               option: flags.contains(.option),
                               control: flags.contains(.control),
                               shift: flags.contains(.shift))
        let verdict = MSKeyCombo.bindability(keyCode: event.keyCode,
                                             command: combo.command,
                                             option: combo.option,
                                             control: combo.control,
                                             shift: combo.shift)
        if event.keyCode == 53 { hint.stringValue = "已取消录制"; stopRecording(); restoreTitles(); return nil }
        guard verdict.isBindable else {
            hint.stringValue = "✗ \(combo.display)：\(verdict.message ?? "不可绑定")"
            if let original = originalCombo { onCommit?(id, original) }   // 立刻装回旧键
            stopRecording(); restoreTitles()
            NSSound.beep()
            return nil
        }
        switch onCommit?(id, combo) ?? .ok {
        case .ok:
            hint.stringValue = "✓ \(id.name) → \(combo.display)" + (verdict == .functionKeyNeedsHint ? "（\(verdict.message!)）" : "")
        case .alreadyTaken(let status):
            hint.stringValue = "✗ \(combo.display) 已被占用（OSStatus \(status)），已恢复原键"
            NSSound.beep()
        case .failed(let status):
            hint.stringValue = "✗ 注册失败（OSStatus \(status)），已恢复原键"
            NSSound.beep()
        }
        stopRecording()
        restoreTitles()
        return nil                                         // 吞掉事件，不让它继续走到控件
    }

    /// 录制开始时记住的原组合，失败时回滚到这里（不留"新旧都不响"的空窗）。
    private var originalCombo: MSKeyCombo?

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    /// 录制结束（无论成功失败）后按当前偏好重画按钮文字。
    func restoreTitles(from prefs: MSAppPreferences? = nil) {
        for r in rows {
            if let prefs {
                r.field.title = comboFor(prefs, r.id).display
            } else {
                r.field.title = comboFor(currentPrefs(), r.id).display
            }
            r.field.contentTintColor = nil
        }
    }

    @objc private func reset() {
        onResetToDefaults?()
    }

    // 由 App 注入，避免直接依赖具体存储类型
    var currentPrefs: () -> MSAppPreferences = { MSAppPreferences() }
    var unregister: (MSHotKeyID) -> Void = { _ in }

    private func comboFor(_ p: MSAppPreferences, _ id: MSHotKeyID) -> MSKeyCombo {
        switch id {
        case .snip: p.hotKeys.snip
        case .pinClipboard: p.hotKeys.pinClipboard
        case .fullScreen: p.hotKeys.fullScreen
        }
    }
}

extension MSHotKeyID {
    var name: String {
        switch self {
        case .snip: "截图"; case .pinClipboard: "贴出剪贴板"; case .fullScreen: "全屏截图"
        }
    }
}

private func label(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: 12)
    f.setContentHuggingPriority(.init(600), for: .horizontal)
    f.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
    return f
}

private func row(_ a: NSView, _ b: NSView) -> NSStackView {
    let s = NSStackView(views: [a, b])
    s.orientation = .horizontal
    s.spacing = 8
    return s
}
