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
        // Same message within 60s is not repeated (`UI-009` rule).
        if text == lastMessage, Date().timeIntervalSince(lastShown) < 60, panel != nil { return }
        lastMessage = text
        lastShown = Date()

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let bg = NSVisualEffectView()
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

        hideWorkItem?.cancel()
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
}
