import AppKit
import Darwin
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

    func writeImage(png: Data) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let written = pb.writeObjects([MSPNGItem(data: png)])
        MSLog.info(.export, "pasteboard write representations=1 ok=\(written)")
        return written
    }
}

/// A pasteboard writer that advertises `public.png` explicitly, so apps that ignore `NSImage`
/// still find a PNG representation (`FR-EXP-001` judgement).
final class MSPNGItem: NSObject, NSPasteboardWriting {
    let data: Data
    init(data: Data) { self.data = data }

    // 只声明 public.png（`Q-04`）。以前这里还挂一条 `.tiff`，内容是拿 NSImage 现算的
    // TIFF——两份表示一旦不一致，粘贴结果就取决于目标应用先问哪一个。
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [NSPasteboard.PasteboardType("public.png")]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type.rawValue {
        case "public.png": return data
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
    /// `--probe-pin <ms>`：真采集 → 真贴窗 → 立刻进编辑态，把窗口留在屏上 ms 毫秒。
    /// `B-028` 换了形态之后必须用眼睛看一次：工具带应当长在图片**下方**，画面不被盖。
    /// 截图由 `make probe-pin` 用 `screencapture -l<windowNumber>` 完成，日志行把 strip/frame 一并打出来。
    /// `--probe-clipboard`：把合成图真写进系统剪贴板，再**读回来**报类型集合、DPI 与 TIFF 是否还在。
    /// `Q-04` 的"只写 PNG"必须由 NSPasteboard 自己回答，不能只看我对代码的印象（判据 `E-062`）。
    func probeClipboard() {
        Task { @MainActor in
                    // 真壳判据：写进系统剪贴板，再**读回来**看声明了哪些类型——"只写 PNG"必须是 NSPasteboard
                    // 自己的回答，不是我对自己代码的印象。合成画面即可，这里裁的是表示集合不是屏幕内容。
                    func report(_ line: String) {
                        MSLog.info(.export, "probe-clipboard \(line)")
                        let url = URL(fileURLWithPath: "/tmp/macshot-probe-clipboard.txt")
                        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
                        else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
                    }
                    let w = 120, h = 80, scale = 2
                    let ctx = CGContext(data: nil, width: w * scale, height: h * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.setFillColor(MSColorRGBA.rgba(30, 90, 200, 1).cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: w * scale, height: h * scale))
                    ctx.setFillColor(MSColorRGBA.rgba(232, 51, 71, 1).cgColor)
                    ctx.fill(CGRect(x: 20, y: 20, width: 100, height: 60))
                    guard let image = ctx.makeImage() else { report("FAIL 合成不出图"); exit(5) }
                    let sentinel = "MACSHOT-CLIPBOARD-SENTINEL-\(Int(Date().timeIntervalSince1970))"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sentinel, forType: .string)
                    let started = ContinuousClock.now
                    let ok = MSClipboardWriter(pasteboard: MSSystemPasteboard()).write(image, scale: scale)
                    let took = started.duration(to: ContinuousClock.now)
                    let pb = NSPasteboard.general
                    let types = (pb.types ?? []).map(\.rawValue).sorted()
                    let pngData = pb.data(forType: NSPasteboard.PasteboardType("public.png")) ?? pb.data(forType: .png)
                    var dpi = "?"
                    if let d = pngData, let src = CGImageSourceCreateWithData(d as CFData, nil),
                       let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                       let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
                       let x = tiff[kCGImagePropertyTIFFXResolution] as? Double { dpi = "\(x)" }
                    report("write ok=\(ok) 像素=\(image.width)x\(image.height) 耗时=\(took)")
                    report("types=\(types)")
                    report("pngBytes=\(pngData?.count ?? -1) dpi=\(dpi)（期望 \(72 * scale)）")
                    // 关键一问：TIFF 还在不在？在的话是**谁**写的——我只交了一个 PNG item，
                    // 系统可能自己派生一份 TIFF 兼容类型，那就不该记在我头上。
                    if let tiff = pb.data(forType: .tiff) {
                        let magic = tiff.prefix(4).map { String(format: "%02x", $0) }.joined()
                        report("tiffBytes=\(tiff.count) magic=\(magic)（49492a00=II*／6d4d002a=MM* ⇒ 是真 TIFF 数据）")
                    } else { report("tiffBytes=nil ⇒ 剪贴板里确实没有 TIFF 表示") }
                    let left = pb.string(forType: .string)
                    report("sentinel 写前=\(sentinel.prefix(23)) 写后=\(left.map { String($0.prefix(23)) } ?? "nil（被 clearContents 吃掉）")")
                    // 对照组：换成系统自带的 NSPasteboardItem、只塞 public.png。
                    // 若 TIFF 仍出现在 types 里 ⇒ 那是 AppKit 自己派生的兼容类型，不是我们的代码写的。
                    if let png = pngData {
                        pb.clearContents()
                        let item = NSPasteboardItem()
                        item.setData(png, forType: NSPasteboard.PasteboardType("public.png"))
                        pb.writeObjects([item])
                        report("对照（NSPasteboardItem 只塞 PNG）types=\((pb.types ?? []).map(\.rawValue).sorted()) "
                               + "tiff=\(pb.data(forType: .tiff) != nil)")
                    }
                    exit(0)
        }
    }

    /// `--probe-hotkey <set|show|restore>`：热键**跨进程**的持久化取证。
    /// `set` 改绑 → 进程退出；`show` 是**下一次启动**读盘并重新注册；`restore` 把键位还回 `F1`。
    /// 三次启动连起来就是 `V-037④` 的机制部分；物理按键那半只能人手（`B-032`）。
    /// `--probe-memory <张数> [宽pt] [高pt]`：`NFR-005` 的两个上限与 `NFR-008` 的回基线，一次跑完出读数。
    /// 用合成画面是有意的：这里要量的是"文档 + 位图 + 窗口"的常驻成本，与屏幕内容无关，
    /// 也就不必等 `T-090` 的签名/授权（cdhash 一变就采不到）。默认 `10 张 3840×2160pt`。
    /// 会在你屏幕上短暂开 N 张贴图，跑完自动关。
    func probeMemory(count: Int, w: Int, h: Int, holdMs: Int) {
        MainActor.assumeIsolated {
                    func report(_ line: String) {
                        MSLog.info(.pin, "probe-memory \(line)")
                        let url = URL(fileURLWithPath: "/tmp/macshot-probe-memory.txt")
                        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
                        else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
                    }
                    func rssMB() -> Double {
                        var info = task_vm_info_data_t()
                        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
                        let kr = withUnsafeMutablePointer(to: &info) {
                            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                            }
                        }
                        // 判据用 resident_size（RSS）。phys_footprint 看不见 CoreGraphics 放在
                        // 可回收区的图像数据：`E-067` 实测 10 张贴图时它报 12MB 而 RSS 报 86MB。
                        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
                    }
                    func physMB() -> Double {
                        var info = task_vm_info_data_t()
                        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
                        let kr = withUnsafeMutablePointer(to: &info) {
                            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                            }
                        }
                        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
                    }
                    let scale = 2
                    let pxW = w * scale, pxH = h * scale
                    let sourceMB = Double(pxW * pxH * 4) / 1_048_576
                    let baseline = rssMB()
                    report("基线 rss=\(String(format: "%.1f", baseline))MB｜源 \(w)x\(h)pt @\(scale)x = \(pxW)x\(pxH)px ≈ \(String(format: "%.1f", sourceMB))MB/张")
                    var last = baseline
                    for i in 0..<count {
                        // 合成画面：这里量的是"文档 + 位图 + 窗口"的常驻成本，与屏幕内容无关，也就不必碰 TCC。
                        let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        // 夹具必须**不可压缩**：纯色 4K 缓冲会被内存压缩器吃掉（第一次实测就是
                        // 第一张 +32MB、后面每张 +0.1MB），量出来的是压缩器的成绩而不是贴图的。
                        // 真截图的熵接近噪声 ⇒ 直接铺随机字节。
                        var buf = [UInt8](repeating: 0, count: pxW * pxH * 4)
                        for k in stride(from: 0, to: buf.count, by: 4) {
                            buf[k] = UInt8.random(in: 0...255)
                            buf[k + 1] = UInt8.random(in: 0...255)
                            buf[k + 2] = UInt8.random(in: 0...255)
                            buf[k + 3] = 255
                        }
                        ctx.data?.copyMemory(from: &buf, byteCount: buf.count)
                        ctx.flush()
                        guard let img = ctx.makeImage() else { report("FAIL 合成不出第 \(i) 张"); break }
                        let rect = MSIntRect(x: 0, y: 0, width: pxW, height: pxH)
                        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: pxW, height: pxH)),
                                                   source: img, scale: scale, sourcePixelRect: rect)
                        let pin = pins.open(content, near: NSPoint(x: 30 + CGFloat(i % 5) * 60, y: 30 + CGFloat(i / 5) * 60),
                                            menu: nil, onClose: { _ in })
                        pin.center(on: NSScreen.screens.first, display: true)
                        let now = rssMB()
                        report("第 \(i + 1) 张 rss=\(String(format: "%.1f", now))MB 本次+\(String(format: "%.1f", now - last))MB 累计+\(String(format: "%.1f", now - baseline))MB")
                        last = now
                    }
                    let peak = last
        // 留一段"贴图都开着"的窗口给外部裁判（vmmap / ps）对数：footprint 与外部读数不一致时，
        // 要能分清是"探针读错了"还是"这条指标本来就不算 CGImage 的后备存储"。
        if holdMs > 600 {
            report("保持 \(holdMs)ms，外部读数请在此期间取（pid=\(getpid())）")
            usleep(UInt32(holdMs) * 1_000)
        }
                    report("（参考）phys_footprint 现在=\(String(format: "%.1f", physMB()))MB——不作判据，理由见 E-067")
                    report("判据：单张增量=\(String(format: "%.1f", (peak - baseline) / Double(max(1, count))))MB "
                           + "vs 上限 源×1.5=\(String(format: "%.1f", sourceMB * 1.5))MB｜"
                           + "\(count) 张累计=\(String(format: "%.1f", peak - baseline))MB vs 上限 330MB")
                    pins.closeAll()
                    usleep(600_000)
                    let after = rssMB()
                    report("关全部贴图后 rss=\(String(format: "%.1f", after))MB（NFR-008：应回基线 ±10%，基线 \(String(format: "%.1f", baseline))）")
                    exit(0)
        }
    }

    func probeHotKeyPersist(mode: String) {
        MainActor.assumeIsolated {
                    func report(_ line: String) {
                        MSLog.info(.hotkey, "probe-hotkey \(line)")
                        let url = URL(fileURLWithPath: "/tmp/macshot-probe-hotkey.txt")
                        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
                        else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
                    }
                    let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("MacShot/preferences.json").path ?? "?"
                    switch mode {
                    case "set":
                        let before = settings.current.hotKeys.snip.display
                        settings.update { $0.hotKeys.snip = MSKeyCombo(keyCode: 25, command: true, option: true) }   // ⌥⌘9（键名表在 `MSKeyCombo.keyNames`，25 才是 9）
                        let after = settings.current.hotKeys.snip.display
                        let r = register(.snip, settings.current.hotKeys.snip)
                        report("set 旧=\(before) 新=\(after) 注册=\(r) 文件=\(path)")
                    case "restore":
                        settings.update { $0.hotKeys.snip = .f1 }
                        let r = register(.snip, settings.current.hotKeys.snip)
                        report("restore 现=\(settings.current.hotKeys.snip.display) 注册=\(r)")
                    default:
                        let combo = settings.current.hotKeys.snip
                        let r = register(.snip, combo)
                        let exists = FileManager.default.fileExists(atPath: path)
                        report("show 读盘=\(exists) snip=\(combo.display) 注册=\(r) "
                               + "pinClipboard=\(settings.current.hotKeys.pinClipboard.display)")
                    }
                    exit(0)
        }
    }

    func probePin(thenExitAfter ms: Int) {
        Task { @MainActor in
                func report(_ line: String) {
                    MSLog.info(.pin, "probe-pin \(line)")
                    let url = URL(fileURLWithPath: "/tmp/macshot-probe-pin.txt")
            // 追加而不是覆写：一次探针有多条读数（采集结果 / 几何 / PNG），只留最后一条等于没写。
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
                }
                // 采集不到（cdhash 换了 ⇒ TCC 重新要授权）时用合成画面：本探针要裁的是**工具带形态**，不是屏幕内容。
                func synthetic(size: NSSize) -> CGImage {
                    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    for y in stride(from: 0, to: Int(size.height), by: 8) {
                        ctx.setFillColor(MSColorRGBA.rgb(UInt8(90 + y / 24), UInt8(120 + y / 40), 150).cgColor)
                        ctx.fill(CGRect(x: 0, y: Double(y), width: size.width, height: 8))
                    }
                    ctx.setFillColor(MSColorRGBA.rgba(232, 51, 71, 1).cgColor)
                    ctx.fill(CGRect(x: size.width / 4, y: size.height / 4, width: size.width / 2, height: size.height / 3))
                    return ctx.makeImage()!
                }
                var source: CGImage
                var scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
                if let display = MSDisplayInventory.current().first {
                    let capturer = CaptureBackendSelector.makeCapturer(backend: CaptureBackendSelector.decide())
                    do {
                        let frame = try await capturer.freeze(display: display)
                        source = frame.image; scale = Int(frame.scale)
                        report("采集成功 \(frame.image.width)x\(frame.image.height) scale=\(frame.scale)")
                    } catch {
                        source = synthetic(size: NSSize(width: 1200, height: 800)); scale = 2
                        report("FAIL 采集失败，改用合成画面：\((error as NSError).code)")
                    }
                } else {
                    source = synthetic(size: NSSize(width: 1200, height: 800)); scale = 2
                    report("FAIL 没有显示器，改用合成画面")
                }
                let px = CGRect(x: source.width / 4, y: source.height / 4,
                                width: source.width / 2, height: source.height / 2)
                guard let crop = source.cropping(to: px) else { report("FAIL 裁不下"); exit(4) }
                let rect = MSIntRect(x: Int(px.origin.x), y: Int(px.origin.y), width: Int(px.width), height: Int(px.height))
                let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: rect.width, height: rect.height)),
                                           source: crop, scale: scale, sourcePixelRect: rect)
                let pin = pins.open(content, near: NSPoint(x: 160, y: 160), menu: nil, onClose: { _ in })
                pin.center(on: NSScreen.screens.first, display: true)
                pin.pinView.isEditing = true          // 立刻进编辑态：工具带应当在图片下方长出来
                report("strip=\(pin.pinView.stripHeight) image=\(pin.pinView.imageRect) frame=\(pin.frame) 逻辑=\(content.logicalSize)")
                // 离屏渲染一张编辑态视图，作为"眼睛"通道：不依赖窗口服务器，也不依赖 TCC。
                if let rep = pin.pinView.bitmapImageRepForCachingDisplay(in: pin.pinView.bounds) {
                    pin.pinView.cacheDisplay(in: pin.pinView.bounds, to: rep)
                    let out = "/tmp/macshot-probe-pin.png"
                    if rep.representation(using: .png, properties: [:]).map({ (try? Data($0).write(to: URL(fileURLWithPath: out))) != nil }) == true {
                        report("PNG=\(out) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                    } else {
                        report("FAIL PNG 写不出")
                    }
                }
                try? await Task.sleep(for: .milliseconds(max(0, ms)))
                exit(0)
        }
    }

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
