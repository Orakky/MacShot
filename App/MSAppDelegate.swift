import AppKit
import MSAnnotate
import MSCapture
import MSCore
import MSExport
import MSHotKey
import MSOverlay
import MSPin
import MSSession
import MSSettings

/// System pasteboard. Encoding happens before this call; here we do exactly one write so a
/// concurrent app cannot observe a half-filled pasteboard (`ADR-014`).
final class MSSystemPasteboard: MSPasteboardWriting, @unchecked Sendable {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func writeImage(png: Data, tiff: Data) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        var writers: [NSPasteboardWriting] = [MSPNGItem(data: png)]
        if !tiff.isEmpty, let image = NSImage(data: tiff) { writers.append(image) }
        let written = pb.writeObjects(writers)
        MSLog.info(.export, "pasteboard write representations=\(writers.count) ok=\(written)")
        return written
    }
}

/// A pasteboard writer that advertises `public.png` explicitly, so apps that ignore `NSImage`
/// still find a PNG representation (`FR-EXP-001` judgement).
final class MSPNGItem: NSObject, NSPasteboardWriting {
    let data: Data
    init(data: Data) { self.data = data }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [NSPasteboard.PasteboardType("public.png"), .tiff]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type.rawValue {
        case "public.png": return data
        case NSPasteboard.PasteboardType.tiff.rawValue:
            return (NSImage(data: data)?.tiffRepresentation) ?? data
        default: return nil
        }
    }
}

@MainActor
final class MSAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = MSSettingsStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("MacShot", isDirectory: true))
    private let pins = MSPinRegistry()
    private lazy var hotKeys = CarbonHotKeyService()
    private var coordinator: MSSessionCoordinator!
    private var statusItem: NSStatusItem?
    private var permissionWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var toastController: MSToast?
    private var hotKeyEditor: MSHotKeyEditor?
    private let autoSnip: Bool

    init(autoSnip: Bool = false) {
        self.autoSnip = autoSnip
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MSLog.info(.app, "launched version=\(Bundle.main.shortVersion) scale=\(NSScreen.main?.backingScaleFactor ?? 0)")
        let backend = CaptureBackendSelector.decide()
        let capturer = CaptureBackendSelector.makeCapturer(backend: backend)
        coordinator = MSSessionCoordinator(capturer: capturer, preferences: settings, pins: pins,
                                          clipboard: MSClipboardWriter(pasteboard: MSSystemPasteboard()))
        coordinator.onToast = { [weak self] text in self?.showToast(text) }
        coordinator.onNeedsPermission = { [weak self] in self?.presentPermissionGate() }

        buildStatusItem()
        registerHotKeys()
        observeDisplays()
        observeResignActive()
        if autoSnip {
            // 取证用：立刻走一遍真实截图路径（含系统授权弹窗）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.coordinator.handle(.snip) }
        }
        MSLog.info(.app, "ready hotkeys=\(self.settings.current.hotKeys.snip.display)/\(self.settings.current.hotKeys.pinClipboard.display)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregisterAll()
        pins.closeAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - hot keys

    private func combos(from prefs: MSAppPreferences) -> [(MSHotKeyID, MSKeyCombo)] {
        [(.snip, prefs.hotKeys.snip),
         (.pinClipboard, prefs.hotKeys.pinClipboard),
         (.fullScreen, prefs.hotKeys.fullScreen)]
    }

    /// 改绑一条：先注销，注册新键；失败则把旧键装回去（FR-HOT-002 判据）。
    @discardableResult
    private func rebind(_ id: MSHotKeyID, to combo: MSKeyCombo) -> MSRegistrationResult {
        let old = combos(from: settings.current).first { $0.0 == id }?.1
        let result = register(id, combo)
        if case .ok = result {
            settings.update { apply(combo, id, to: &$0) }
            showToast("\(id.name) → \(combo.display)")
        } else if let old {
            _ = register(id, old)
            showToast("\(combo.display) 注册失败，已恢复 \(old.display)")
        }
        hotKeyEditor?.restoreTitles(from: settings.current)
        return result
    }

    private func apply(_ combo: MSKeyCombo, _ id: MSHotKeyID, to prefs: inout MSAppPreferences) {
        switch id {
        case .snip: prefs.hotKeys.snip = combo
        case .pinClipboard: prefs.hotKeys.pinClipboard = combo
        case .fullScreen: prefs.hotKeys.fullScreen = combo
        }
    }

    @discardableResult
    private func register(_ id: MSHotKeyID, _ combo: MSKeyCombo) -> MSRegistrationResult {
        hotKeys.unregister(id)
        return hotKeys.register(combo, id: id) { [weak self] in
            Task { @MainActor in self?.coordinator.handle(id) }
        }
    }

    private func registerHotKeys() {
        for (id, combo) in combos(from: settings.current) {
            let result = register(id, combo)
            if case .alreadyTaken = result { showToast("热键 \(combo.display) 已被占用") }
        }
    }

    // MARK: - status item

    /// 左键＝直接截图，右键（或 ⌃ 点击）＝菜单。挂 item.menu 会让左键只能弹菜单，
    /// 所以这里不设 menu，改由按钮自己分发（FR-HOT-013）。
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let glyph = MSStatusGlyph.image() {
            item.button?.image = glyph
            item.button?.imagePosition = .imageOnly
            MSLog.info(.app, "status glyph=\(MSStatusGlyph.pointSize)pt template ink=\(String(format: "%.2f", MSStatusGlyph.inkCoverage(of: glyph)))")
        } else {
            // 素材没注入也要留得下入口：回落文字，并把缺素材这件事说出口（不静默）。
            MSLog.error(.app, "status glyph missing（\(MSStatusGlyph.resourceName).svg 不在 bundle 里）→ 回落 ✂ 文本")
            item.button?.title = "✂"
        }
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "左键截图（\(settings.current.hotKeys.snip.display)）· 右键菜单"
        let menu = NSMenu()
        menu.addItem(withTitle: "截图", action: #selector(snip), keyEquivalent: "").target = self
        menu.addItem(withTitle: "全屏截图", action: #selector(snipFullScreen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "贴出剪贴板图像", action: #selector(pinClipboard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "关闭所有贴图", action: #selector(closePins), keyEquivalent: "w").target = self
        menu.addItem(.separator())
        let perm = NSMenuItem(title: "屏幕录制权限：检测中…", action: #selector(openPermissionSettings), keyEquivalent: "")
        perm.target = self
        menu.addItem(perm)
        permissionMenuItem = perm
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "关于 MacShot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MacShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusMenu = menu
        statusItem = item
        refreshPermissionMenuItem()
    }

    private func refreshPermissionMenuItem() {
        let granted = PermissionProbe.screenRecording() == .granted
        permissionMenuItem?.title = granted ? "屏幕录制权限：已授予" : "⚠ 屏幕录制权限：未授予"
        // 回读而不是打印"打算设的值"：这一行拿到 nil 就说明引用没握住（旧 bug 的形状就是查不到项、静默不更新）。
        MSLog.info(.app, "permission menu row=\(self.permissionMenuItem?.title ?? "nil（行没握住）")")
    }

    /// 持引用而不是按标题查：标题一旦从"检测中…"改成结果，再按原标题查就永远是 nil，
    /// 这一行就会永远停在第一次的值上（实测过的失效形状）。
    private var permissionMenuItem: NSMenuItem?

    /// `--snip-then-cancel <ms>`：开遮罩 → 冻住 → 到点走**和 Esc 同一条**取消路径退出。
    /// 给 `scripts/probe-freeze.sh` 用：连拍两张遮罩图必须逐字节相同（背景真被冻住），
    /// 同时校验真剪贴板的哨兵没被动过（`FR-SESS-002` 判据④）。
    func probeSnipThenCancel(after ms: Int) {
        coordinator.handle(.snip)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) { [weak self] in
            guard let self else { return }
            MSLog.info(.session, "probe cancel visible=\(self.coordinator.overlayVisible)")
            self.coordinator.cancelSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exit(0) }
        }
    }

    /// `--probe-menu`：把"权限行这次真的换过话"做成可打印的证据。
    /// `attached` 是关键——握住的对象必须就是菜单里那一行，否则写了也白写。
    func probeStatusMenu(refreshes: Int = 3) {
        for i in 0..<max(1, refreshes) {
            refreshPermissionMenuItem()
            let attached = self.statusMenu?.items.contains(where: { $0 === self.permissionMenuItem }) ?? false
            MSLog.info(.app, "probe-menu#\(i) rows=\(self.statusMenu?.items.count ?? -1) attached=\(attached) permRow=\(self.permissionMenuItem?.title ?? "nil")")
        }
    }

    private var statusMenu: NSMenu?

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { coordinator.handle(.snip); return }
        let wantsMenu = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if wantsMenu { popStatusMenu() } else { coordinator.handle(.snip) }
    }

    private func popStatusMenu() {
        guard let item = statusItem, let menu = statusMenu else { return }
        item.menu = menu
        item.button?.performClick(nil)
    }

    // 菜单关闭后必须收回 item.menu，否则下一次左键又只会弹菜单
    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu { statusItem?.menu = nil }
    }

    /// 遮罩开着却失去活跃状态（系统弹窗、别的 app 抢前台）→ 立刻收窗，绝不留一层吃点击的窗。
    private func observeResignActive() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.coordinator.overlayVisible else { return }
                MSLog.info(.app, "resigned active with overlay open → cancel session")
                self.coordinator.cancelSession()
            }
        }
    }

    @objc private func snip() {
        if coordinator.overlayVisible { coordinator.cancelSession() } else { coordinator.handle(.snip) }
    }
    @objc private func snipFullScreen() { coordinator.handle(.fullScreen) }
    @objc private func pinClipboard() { coordinator.handle(.pinClipboard) }
    @objc private func closePins() { pins.closeAll() }

    @objc private func openPermissionSettings() {
        let urls = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Screenshots"]
        for raw in urls where NSWorkspace.shared.open(URL(string: raw)!) { return }
        showToast("请手动打开 系统设置 → 隐私与安全性 → 屏幕录制")
    }

    // MARK: - permission gate (UI-007)

    private func presentPermissionGate() {
        refreshPermissionMenuItem()
        guard permissionWindow == nil else { permissionWindow?.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "需要屏幕录制权限"
        panel.isReleasedWhenClosed = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        content.addArrangedSubview(label("截图需要系统允许 MacShot 读取屏幕内容。", weight: .semibold))
        content.addArrangedSubview(label("1. 点「打开系统设置」→ 隐私与安全性 → 屏幕录制与系统音频录制\n2. 勾选 MacShot（列表里现在应该有它：我们已实际尝试过一次采集）\n3. 点「重启 MacShot」让授权生效"))
        content.addArrangedSubview(label("若列表里没有 MacShot，或它显示为「已拒绝」且无法勾选：先前拒绝过一次，系统就不再弹框了——点「清除旧授权记录」后重启再试。",
                                         color: .secondaryLabelColor))
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -36).isActive = true
        buttons.addArrangedSubview(button("打开系统设置") { [weak self] in self?.openPermissionSettings() })
        buttons.addArrangedSubview(button("清除旧授权记录") {
            // 之前拒绝过一次 → 系统不再弹框，列表项也锁在"已拒绝"。tccutil reset 是唯一出路。
            MSTcc.resetScreenCapture()
            self.showToast("已清除授权记录，请点「打开系统设置」重新勾选")
        })
        buttons.addArrangedSubview(button("重启 MacShot") {
            let url = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                NSApplication.shared.terminate(nil)
            }
        })
        content.addArrangedSubview(buttons)
        let host = NSView()
        host.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor),
        ])
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 250)
        panel.contentView = host
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = panel
        MSLog.info(.app, "permission gate shown")
    }

    // MARK: - settings (UI-005, first pass: the values that change behaviour today)

    @objc private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label("提交动作（Enter / 双击选区）", weight: .semibold))
        let seg = NSSegmentedControl(labels: MSAppPreferences.CommitBehavior.allCases.map(\.label),
                                     trackingMode: .selectOne, target: self, action: #selector(commitChanged(_:)))
        seg.tag = Int(MSAppPreferences.CommitBehavior.allCases.firstIndex(of: settings.current.commitBehavior) ?? 0)
        seg.selectedSegment = seg.tag
        stack.addArrangedSubview(seg)

        stack.addArrangedSubview(label("热键", weight: .semibold))
        let editor = MSHotKeyEditor()
        editor.currentPrefs = { [weak self] in self?.settings.current ?? MSAppPreferences() }
        editor.unregister = { [weak self] id in self?.hotKeys.unregister(id) }
        editor.onCommit = { [weak self] id, combo in self?.rebind(id, to: combo) ?? .failed(-1) }
        editor.onResetToDefaults = { [weak self] in self?.resetHotKeys() }
        stack.addArrangedSubview(editor.build(prefs: settings.current))
        editor.restoreTitles(from: settings.current)
        hotKeyEditor = editor
        stack.addArrangedSubview(label("MacBook 上 F1/F3 可能被系统当作亮度/调度键：需在系统设置开启「将 F1、F2 等键用作标准功能键」，或按 fn。",
                                       color: .secondaryLabelColor))

        stack.addArrangedSubview(label("导出", weight: .semibold))
        let dir = NSTextField(string: settings.current.export.directory)
        dir.placeholderString = "~/Pictures/MacShot"
        dir.target = self
        dir.action = #selector(directoryChanged(_:))
        dir.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(labeledRow("目录", dir))
        let tpl = NSTextField(string: settings.current.export.namingTemplate)
        tpl.target = self
        tpl.action = #selector(templateChanged(_:))
        tpl.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(labeledRow("命名模板", tpl))

        stack.addArrangedSubview(label("屏幕录制权限：\(PermissionProbe.screenRecording() == .granted ? "已授予" : "未授予")",
                                       color: .secondaryLabelColor))

        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
        ])
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func resetHotKeys() {
        let defaults = MSAppPreferences.HotKeys.standard
        for (id, combo) in combos(from: MSAppPreferences(hotKeys: defaults)) { _ = register(id, combo) }
        settings.update { $0.hotKeys = defaults }
        hotKeyEditor?.restoreTitles(from: settings.current)
        showToast("热键已恢复默认")
    }

    @objc private func commitChanged(_ sender: NSSegmentedControl) {
        guard let value = MSAppPreferences.CommitBehavior.allCases[safe: sender.selectedSegment] else { return }
        settings.update { $0.commitBehavior = value }
        showToast("提交动作 → \(value.label)")
    }

    @objc private func directoryChanged(_ sender: NSTextField) {
        settings.update { $0.export.directory = sender.stringValue }
        showToast("导出目录 → \(sender.stringValue)")
    }

    @objc private func templateChanged(_ sender: NSTextField) {
        settings.update { $0.export.namingTemplate = sender.stringValue }
        let preview = MSNamingTemplate(sender.stringValue).expand(.init(pixelSize: MSIntSize(width: 860, height: 500), scale: 2))
        showToast("文件名示例 → \(preview).png")
    }

    // MARK: - displays

    private func observeDisplays() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MSLog.debug(.app, "did become active")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MSLog.info(.app, "screen parameters changed pins=\(self.pins.count)")
            Task { @MainActor in
                self.pins.reanchorAll(to: NSScreen.main)
                self.refreshPermissionMenuItem()
            }
        }
    }

    // MARK: - toast (UI-009)

    private func showToast(_ text: String) {
        if toastController == nil { toastController = MSToast() }
        toastController?.show(text)
        MSLog.info(.app, "toast: \(text)")
    }

    // MARK: - small builders

    private func label(_ text: String, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = .systemFont(ofSize: 12, weight: weight)
        f.textColor = color
        f.isSelectable = false
        return f
    }

    private func button(_ title: String, action: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: ButtonBox.shared, action: #selector(ButtonBox.fire(_:)))
        b.tag = ButtonBox.shared.nextKey()
        b.bezelStyle = .rounded
        ButtonBox.shared.register(b.tag, action)
        return b
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSStackView {
        let row = NSStackView(views: [label(title), control])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }
}

/// Targets for locally-created buttons; ARC otherwise releases the closures.
@MainActor final class ButtonBox {
    static let shared = ButtonBox()
    private var actions: [Int: () -> Void] = [:]
    private var counter = 0
    func nextKey() -> Int { counter += 1; return counter }
    func register(_ key: Int, _ action: @escaping () -> Void) { actions[key] = action }
    @objc func fire(_ sender: NSButton) { actions[sender.tag]?() }
}

extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }

extension Bundle { var shortVersion: String { (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0" } }
