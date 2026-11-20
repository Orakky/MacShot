import AppKit
import MSCore

/// One-shot bottom-centre notice (`design/screens.md#UI-009`). Not a system banner: those need
/// notification permission and can be missed while the user is in another app.
@MainActor
final class MSToast {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var lastMessage: String = ""
    private var lastShown: Date = .distantPast

    func show(_ text: String) {
        // 同一条文案 60 秒内不重复刷屏（UI-009），但**必须重新排隐藏计时**——
        // 以前这里是 return，配合"新建 panel"就变成：旧的那条既不消失也不再被管。
        if text == lastMessage, Date().timeIntervalSince(lastShown) < 60, panel != nil {
            scheduleHide()
            return
        }
        lastMessage = text
        lastShown = Date()

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2

        let panel = self.panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
                                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 贴图（`MSPinLevel.current`）就是 statusBar(25)：同级 ⇒ 谁后 orderFront 谁在上面，
        // toast 会被刚贴出的图压住（11-20 用户实测"藏在其他窗口下方"）。压过它一级。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let bg = NSVisualEffectView()   // 每个 panel 只留一份内容视图：下面 setContentView 前会清掉旧的
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        bg.layer?.masksToBounds = true
        bg.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -14),
        ])
        let textWidth = min(520.0, label.fittingSize.width + 28)
        bg.frame = NSRect(x: 0, y: 0, width: textWidth, height: 40)
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView = bg
        panel.setContentSize(NSSize(width: textWidth, height: 40))

        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 64))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        scheduleHide()
    }

    /// 隐藏永远挂在"当前这一个 panel"上，并且每次 show 都重排：
    /// 判据是"toast 出现后必然消失"，不是"我排过一个计时器"。
    private func scheduleHide() {
        hideWorkItem?.cancel()
        guard let panel else { return }
        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// 探针判据用：当前是否有一条 toast 正显示着。
    var isOnScreenForProbe: Bool { panel?.isVisible == true && (panel?.alphaValue ?? 0) > 0.5 }
    var levelForProbe: Int { Int(panel?.level.rawValue ?? -1) }
}
