import AppKit
import Foundation
import MSAnnotate
import MSCapture
import MSCore
import MSExport
import MSHotKey
import MSOverlay
import MSPin
import MSSettings

public enum MSSessionPhase: String, Sendable { case idle, frozen, selecting, editing, committing, failed, gate }

public enum MSSessionEvent: Sendable, Equatable {
    case hotKeyPressed(MSHotKeyID)
    case permissionState(PermissionState)
    case overlayShown
    case selectionChanged(width: Int, height: Int)
    case drawBegan
    case drawEnded
    /// 元素层数量变了（提交/删除/清空/撤销都会报）。`hasElements` 的唯一维护入口，
    /// 由 `MSOverlayView.document.didSet` 生产——不靠"某处记得调一次"。
    case colorCopyRequested(String)
    case elementCountChanged(Int)
    case commitRequested(MSCommitIntent)
    case effectsFinished
    case captureFailed(String)
}

public enum MSSessionEffect: Sendable, Equatable {
    case freeze
    case showOverlay
    case closeOverlay
    case restoreFocus
    case bakeAndCopy
    case openPin
    case saveToFile(panel: Bool)
    case showPermissionGate
    case toast(String)
    /// 改选区尺寸把已有标注清空了，必须显式提示（`ST-001` 行 7、Q-11 推荐档 A）。
    /// 文案只有一个家：`MSSessionCopy.annotationCleared`。
    /// 把取样色串写进剪贴板（`FR-CAP-016` 的 `C`）。
    case copyColorText(String)
    case warnClearAnnotations
    case log(String)
}

/// 会话侧给用户看的文案。**唯一一处**落这条字符串的地方，等 ADR-016（`MSStrings`）签字后整族迁过去。
public enum MSSessionCopy {
    /// 改选区尺寸清空标注的提示。不许暗示可撤销——清空同时重置了历史（`Q-11`）。
    public static let annotationCleared = "选区尺寸已改变，原有标注已清空（无法撤销）"
}

/// Pure state machine, head-testable without a window (`ST-001`, `V-008`).
public struct MSSessionReducer: Sendable {
    public private(set) var phase: MSSessionPhase = .idle
    public private(set) var hasSelection = false
    public private(set) var hasElements = false
    public var pendingIntent: MSCommitIntent?

    public init() {}

    public mutating func handle(_ event: MSSessionEvent) -> [MSSessionEffect] {
        switch (phase, event) {
        case (_, .permissionState(.denied)) where phase == .idle:
            phase = .gate
            return [.showPermissionGate]

        case (.idle, .hotKeyPressed(.snip)):
            phase = .frozen
            return [.freeze, .showOverlay]

        case (.idle, .hotKeyPressed(.fullScreen)):
            phase = .committing
            pendingIntent = .pin
            return [.freeze, .bakeAndCopy, .closeOverlay, .restoreFocus]

        case (.idle, .hotKeyPressed(.pinClipboard)):
            return [.openPin]

        case (.frozen, .overlayShown):
            phase = .selecting
            return []

        case (.gate, .permissionState(.granted)):
            phase = .idle
            return [.toast("需要重启 MacShot 才能生效")]

        case (.gate, .permissionState(.denied)):
            return [.showPermissionGate]

        case (.selecting, .selectionChanged(let w, let h)):
            hasSelection = w > 3 && h > 3
            // 行 7：清空是遮罩那边做的，这里只负责"有元素就要提示"。
            // 视图刻意把本通知排在清空之前，所以 `hasElements` 这里还是清空前的真值。
            var effects: [MSSessionEffect] = [.log("selection \(w)x\(h)")]
            if hasElements {
                hasElements = false
                effects.append(.warnClearAnnotations)
            }
            return effects

        case (.selecting, .elementCountChanged(let count)), (.editing, .elementCountChanged(let count)):
            hasElements = count > 0
            return [.log("elements=\(count)")]

        case (.selecting, .drawBegan):
            guard hasSelection else { return [.toast("先框选区域")] }
            phase = .editing
            return []

        case (.editing, .drawEnded):
            hasElements = true
            phase = .selecting
            return [.log("element committed")]

        case (.frozen, .commitRequested(.cancel)):
            phase = .idle
            return [.closeOverlay, .restoreFocus]

        case (.selecting, .colorCopyRequested(let text)), (.editing, .colorCopyRequested(let text)):
            return [.copyColorText(text)]

        case (.selecting, .commitRequested(let intent)), (.editing, .commitRequested(let intent)):
            guard hasSelection || intent == .cancel else { return [.toast("先框选区域")] }
            if intent == .cancel {
                phase = .idle
                return [.closeOverlay, .restoreFocus]
            }
            phase = .committing
            pendingIntent = intent
            switch intent {
            case .copy: return [.closeOverlay, .bakeAndCopy, .restoreFocus]
            case .pin: return [.closeOverlay, .openPin, .restoreFocus]   // 剪贴板那一份在 commit(.pin) 里做（Q-05），effect 列表只描述路由
            case .savePanel: return [.closeOverlay, .saveToFile(panel: true), .restoreFocus]
            case .quickSave: return [.closeOverlay, .saveToFile(panel: false), .restoreFocus]
            case .cancel: return [.closeOverlay, .restoreFocus]
            }

        case (.committing, .effectsFinished):
            phase = .idle
            hasSelection = false
            hasElements = false
            pendingIntent = nil
            return []

        case (.frozen, .captureFailed(let reason)), (.selecting, .captureFailed(let reason)),
             (.editing, .captureFailed(let reason)):
            phase = .failed
            // reason 已是给用户看的人话（由 reportCaptureFailure 传入），这里不再加前缀。
            return [.closeOverlay, .restoreFocus, .toast(reason)]

        case (.failed, .effectsFinished):
            phase = .idle
            return []

        default:
            // Illegal migration: log and stay put rather than inventing a transition
            // (state-machines.md ST-001 "非法迁移").
            // Bound first: MSLog takes an escaping autoclosure, which cannot capture a
            // mutating struct's self.
            let rejected = "illegal migration phase=\(phase.rawValue) event=\(event)"
            MSLog.error(.session, rejected)
            return [.log("rejected \(phase.rawValue)+\(event)")]
        }
    }
}

/// Wires the modules together and performs the effects. This is the only place in the kit that
/// owns live UI objects (`overview.md` §4).
@MainActor
public final class MSSessionCoordinator: NSObject, MSOverlayDelegate, MSPinDelegate {
    private let capturer: any ScreenCapturing
    private let preferences: any MSReadingPreferences
    private let pins: MSPinRegistry
    private let baker = MSBitmapBaker()
    private let clipboard: MSClipboardWriter
    private let fileExporter = MSFileExporter()
    private var reducer = MSSessionReducer()

    /// internal 只读（测试缝）：测试用它断言"窗创建了但没呈现"，生产代码不读。
    private(set) var overlay: MSOverlayWindow?
    private var frozenFrame: MSCaptureFrame?
    private var displaySnapshot: [MSDisplay] = []
    private var activeDisplay: MSDisplay?
    private var frontAppBeforeSession: NSRunningApplication?

    /// 测试入口（`B-029` 11-17 裁决）：生产路径恒为 true；false 时遮罩窗**创建但不呈现**，
    /// 于是"Effect → 分发器 → onToast"这条端到端判据可以在不劫持开发者屏幕的前提下跑。
    /// 判据本身要断言 `isVisible == false`，不是靠"我觉得没弹"。
    var presentsOverlay = true

    public var onToast: ((String) -> Void)?
    public var onNeedsPermission: (() -> Void)?

    /// 向系统申请屏幕录制权限的动作做成可注入的：单测必须能跑拒绝路径而不真的弹系统框。
    var permissionRequester: () -> PermissionState = { PermissionProbe.requestScreenRecording() }
    /// 本次进程内向系统申请过几次，供断言与日志。
    private(set) var permissionRequestCount = 0
    private var didAskSystemForPermission = false

    public init(capturer: any ScreenCapturing, preferences: any MSReadingPreferences,
                pins: MSPinRegistry, clipboard: MSClipboardWriter) {
        self.capturer = capturer
        self.preferences = preferences
        self.pins = pins
        self.clipboard = clipboard
    }

    // MARK: - entry points

    public func handle(_ hotKey: MSHotKeyID) {
        MSLog.info(.session, "hotkey \(hotKey)")
        switch hotKey {
        case .snip: startSnip()
        case .fullScreen: startFullScreen()
        case .pinClipboard: pinFromPasteboard()
        }
    }

    private func run(_ event: MSSessionEvent) {
        for effect in reducer.handle(event) { perform(effect) }
        if reducer.phase == .idle { frozenFrame = nil }   // 会话结束才是冻结帧的释放点
    }

    /// 用户能看懂的失败说明，绝不把 NSError 原样甩到屏幕上（`UI-009`）。
    /// 采集被系统拒了 ⇒ 向 TCC 申请权限。每个进程生命周期内只申请一次：同一身份被拒过一次后
    /// 系统不会再弹框，反复申请只会把"每次启动都要权限"的观感放大（2026-11-16 用户报告）。
    func requestPermissionOnce() {
        guard !didAskSystemForPermission else {
            MSLog.info(.capture, "capture.perm-missing 本次启动已申请过(\(self.permissionRequestCount))，不再触发系统框")
            return
        }
        didAskSystemForPermission = true
        permissionRequestCount += 1
        let after = permissionRequester()
        MSLog.error(.capture, "capture.perm-missing after request=\(after.rawValue)")
    }

    private func reportCaptureFailure(_ detail: String) {
        frozenFrame = nil
        run(.captureFailed(detail))
        finishEffects()
        onNeedsPermission?()
    }

    /// 唯一面向用户的失败文案来源：说清"发生了什么 + 下一步做什么"。
    private static func failureMessage(for error: Error) -> String {
        MSCaptureError.isPermissionDenied(error)
            ? "截不到屏幕内容：需要在 系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制 勾选 MacShot，然后重启它"
            : "截图失败：\((error as NSError).localizedDescription)"
    }

    private func startSnip() {
        guard reducer.phase == .idle else {
            // 再按一次截图键 = 取消当前会话。遮罩是全屏模态，键收不到时这条是不用重启电脑的出路。
            let busyPhase = reducer.phase.rawValue
            MSLog.info(.session, "snip pressed while active (\(busyPhase)) → cancel")
            cancelSession()
            return
        }
        displaySnapshot = MSDisplayInventory.current()
        guard let display = MSDisplayInventory.display(under: NSEvent.mouseLocation, in: displaySnapshot) else {
            onToast?("找不到显示器"); return
        }
        activeDisplay = display
        frontAppBeforeSession = NSWorkspace.shared.frontmostApplication
        // 关键：这里**不能**因为 preflight 说"未授权"就早退。macOS 是在应用真的尝试采集时，
        // 才把它加进「屏幕录制」列表并弹系统授权框；早退会让列表里永远没有 MacShot，
        // 用户无从勾选 → 死循环（2026-11-16 就是这个现象：一直要权限、永远截不了图）。
        // preflight 只用于记日志与提示文案。
        let preflight = PermissionProbe.screenRecording()
        if preflight != .granted {
            MSLog.info(.capture, "preflight=\(preflight.rawValue); 仍会尝试采集以触发系统授权流程")
        }
        let started = ContinuousClock.now
        run(.hotKeyPressed(.snip))
        Task { @MainActor in
            do {
                let frame = try await self.capturer.freeze(display: display)
                self.frozenFrame = frame
                MSLog.info(.capture, "t.hotkey→frozen \(started.duration(to: ContinuousClock.now))")
                let window = MSOverlayWindow(display: display, frame: frame.image)
                window.overlayDelegate = self
                // 设置里的默认样式必须在这里进视图：A-11 的判据是"改了真的生效"，不是"存下来了"。
                window.overlayView.applyDefaults(self.preferences.current.annotationStyle())
                self.applyChromeAppearance(window, prefs: self.preferences.current)
                window.overlayView.autoLoupeWhileDragging = self.preferences.current.showMagnifierWhileDragging
                self.overlay = window
                if self.presentsOverlay { window.present() }
                self.run(.overlayShown)
            } catch let error as MSCaptureError {
                self.frozenFrame = nil
                switch error {
                case .permissionMissing:
                    requestPermissionOnce()
                    self.run(.captureFailed("permission"))
                    self.finishEffects()
                    self.onNeedsPermission?()
                default:
                    self.reportCaptureFailure(Self.failureMessage(for: error))
                }
            } catch {
                self.reportCaptureFailure(Self.failureMessage(for: error))
            }
        }
    }

    private func startFullScreen() {
        displaySnapshot = MSDisplayInventory.current()
        guard let display = MSDisplayInventory.display(under: NSEvent.mouseLocation, in: displaySnapshot) else { return }
        activeDisplay = display
        frontAppBeforeSession = NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            do {
                let frame = try await self.capturer.freeze(display: display)
                self.frozenFrame = frame
                self.commit(intent: preferences.current.commitBehavior == .copy ? .copy : .pin,
                            selection: display.logicalFrame, document: nil)
            } catch {
                self.onToast?("截图失败：\(error.localizedDescription)")
            }
        }
    }

    public func pinFromPasteboard() {
        guard let nsImage = NSImage(pasteboard: .general), let cg = cgImage(from: nsImage) else {
            onToast?("剪贴板里没有图像")
            MSLog.info(.pin, "pasteboard has no image")
            return
        }
        let scale = Int((NSScreen.main?.backingScaleFactor ?? 2).rounded())
        let content = MSPinContent.bitmap(cg, scale: scale)
        let origin = NSPoint(x: NSEvent.mouseLocation.x - content.logicalSize.width / 2,
                            y: NSEvent.mouseLocation.y - content.logicalSize.height / 2)
        let pin = pins.open(content, near: origin, menu: pinMenu(), onClose: { _ in })
        pin.pinDelegate = self
        MSLog.info(.pin, "pinned pasteboard \(cg.width)x\(cg.height) scale=\(scale)")
    }

    // MARK: - commit

    private func commit(intent: MSCommitIntent, selection: CGRect?, document: MSAnnotationDocument?) {
        guard let frame = frozenFrame, let display = activeDisplay else { return }
        let globalSel = selection?.offsetBy(dx: 0, dy: 0) ?? display.logicalFrame
        guard let cropped = RegionCropper.crop(frame, logicalSelection: globalSel, in: display) else {
            onToast?("选区无效"); return
        }
        // `G-03` 要的是"各出口占比"，所以标记必须**每个出口都打、格式统一**，
        // 而不是只有 pin 有一行自定义日志。计数脚本 `scripts/usage-report.sh` 只认这一条。
        MSLog.info(.session, "commit intent=\(intent.rawValue)")
        let doc = document ?? MSAnnotationDocument(canvasSize: cropped.pixelSize)
        guard let image = baker.bake(doc, source: cropped.image) ?? Optional(cropped.image) else { return }
        switch intent {
        case .copy, .savePanel, .quickSave:
            Task { @MainActor in
                let scale = Int(display.scale)
                switch intent {
                case .copy:
                    let ok = self.clipboard.write(image, scale: scale)
                    self.onToast?(ok ? "已复制 \(image.width)×\(image.height)" : "剪贴板写入失败")
                case .quickSave, .savePanel:
                    let url = self.exportDirectory()
                    if intent == .savePanel { self.presentSavePanel(image: image, scale: scale, directory: url) }
                    else {
                        let req = MSExportRequest(image: image, scale: scale,
                                                  format: self.preferences.current.export.format,
                                                  jpegQuality: self.preferences.current.export.jpegQuality,
                                                  naming: MSNamingTemplate(self.preferences.current.export.namingTemplate),
                                                  directory: url)
                        switch self.fileExporter.save(req) {
                        case .written(let path, _): self.onToast?("已保存 \(URL(fileURLWithPath: path).lastPathComponent)")
                        case .failed(let e): self.onToast?("保存失败：\(e)")
                        }
                    }
                case .cancel, .pin:
                    break        // 这两个出口不写文件；显式列出，不用 default 兜
                }
                self.finishEffects()
            }
        case .pin:
            let content = MSPinContent(document: doc, source: cropped.image, scale: Int(display.scale),
                                       sourcePixelRect: cropped.sourcePixelRect)
            let origin = NSPoint(x: globalSel.midX - content.logicalSize.width / 2,
                                y: globalSel.midY - content.logicalSize.height / 2)
            let pin = pins.open(content, near: origin, menu: pinMenu(), onClose: { _ in })
            pin.pinDelegate = self
            pin.center(on: screen(containing: globalSel), display: true)
            // `Q-05`：「置顶」本身就带复制。Snipaste 的用法就是钉住参考图、然后拿去粘贴别处，
            // 少一次 ⌘C 是这条出口存在的理由；复制失败也不收回贴图——两件事各自成立。
            let ok = clipboard.write(image, scale: Int(display.scale))
            MSLog.info(.export, "commit pin clipboard=\(ok) pixels=\(image.width)x\(image.height)")
            onToast?(ok ? "已贴出并复制 \(image.width)×\(image.height)" : "已贴出（剪贴板写入失败）")
            finishEffects()
        case .cancel:
            finishEffects()
        }
    }

    private func finishEffects() {
        closeOverlay()
        run(.effectsFinished)
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
    }

    private func exportDirectory() -> URL {
        let raw = (preferences.current.export.directory as NSString).expandingTildeInPath
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    private func presentSavePanel(image: CGImage, scale: Int, directory: URL) {
        let panel = NSSavePanel()
        panel.directoryURL = directory
        let base = MSNamingTemplate(preferences.current.export.namingTemplate).expand(
            .init(pixelSize: MSIntSize(width: image.width, height: image.height), scale: scale))
        panel.nameFieldStringValue = "\(base).\(preferences.current.export.format == .png ? "png" : "jpg")"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let data = self.preferences.current.export.format == .png
                ? MSImageEncoder.png(image, scale: scale)
                : MSImageEncoder.jpeg(image, scale: scale, quality: self.preferences.current.export.jpegQuality)
            do { try data?.write(to: url, options: .atomic); self.onToast?("已保存 \(url.lastPathComponent)") }
            catch { self.onToast?("保存失败：\(error.localizedDescription)") }
        }
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - MSOverlayDelegate

    /// `ST-001` 行 7 的入口。此前这条是 `nonisolated` 的**空函数**——
    /// 意味着行 7 在生产里从来没人喂过事件，清空提示再怎么修也响不了（`E-058`）。
    /// 注意：**不能**在这里调 `finishEffects()`——它的语义是"会话结束（关窗 + effectsFinished）"。
    /// 11-17 我就这么写错过一次，症状是选区一变遮罩就消失、日志刷 `illegal migration effectsFinished`。
    /// `run()` 本身已经就地执行效果。
    public func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {
        let w = Int((rect?.width ?? 0).rounded()), h = Int((rect?.height ?? 0).rounded())
        run(.selectionChanged(width: w, height: h))
    }

    public func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) {
        run(.commitRequested(intent))
        commit(intent: intent, selection: overlay.overlayView.globalSelection,
               document: overlay.overlayView.annotationDocument)
    }

    /// `ST-001` 行 9/10 的入口：绘制起止走事件，元素数单独一条，
    /// 这样删除/撤销/清空都能让 `hasElements` 保持真值。
    public func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase) {
        if case .began = phase { run(.drawBegan) }
        if case .ended(let count) = phase { run(.elementCountChanged(count)) }
    }

    /// 设置窗改了明暗/放大镜开关后调用：**已经开着的遮罩立刻跟着变**，
    /// 不用等下一次截图（`M-5` 准出①要求"即时生效（无重启）"）。
    @MainActor
    public func reapplyChromePreferences() {
        let prefs = preferences.current
        if let overlay {
            applyChromeAppearance(overlay, prefs: prefs)
            overlay.overlayView.autoLoupeWhileDragging = prefs.showMagnifierWhileDragging
            overlay.overlayView.needsDisplay = true
            MSLog.info(.settings, "chrome prefs reapplied live appearance=\(prefs.appearance.rawValue) "
                       + "magnifier=\(prefs.showMagnifierWhileDragging)")
        }
    }

    /// `appearance` 落地的唯一地方：把设置翻成 `NSAppearance` 挂到窗上。
    /// 视图不自己判断明暗（那会有两套真相）；它读 `effectiveAppearance`，于是被覆盖后自动跟着变。
    private func applyChromeAppearance(_ window: MSOverlayWindow, prefs: MSAppPreferences) {
        switch prefs.appearance {
        case .system: window.appearance = nil
        case .light:  window.appearance = NSAppearance(named: .aqua)
        case .dark:   window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    public func overlay(_ overlay: MSOverlayWindow, didPickColor text: String) {
        // 同 `selectionDidChange` 那条教训：**不要**在这里调 `finishEffects()`——它的语义是"会话结束"。
        guard !text.isEmpty else { onToast?("没有可复制的颜色"); return }
        run(.colorCopyRequested(text))
    }

    public func overlay(_ overlay: MSOverlayWindow, elementCount: Int) {
        run(.elementCountChanged(elementCount))
    }

    public func overlayDidCancel(_ overlay: MSOverlayWindow) {
        run(.commitRequested(.cancel))
    }

    public func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage? {
        guard let frame = frozenFrame, let display = activeDisplay else { return frozenFrame?.image }
        let global = rect.offsetBy(dx: overlay.frame.minX, dy: overlay.frame.minY)
        guard let pixel = display.pixelRect(forLogical: global) else { return nil }
        return frame.image.cropping(to: pixel.cgRect)
    }

    public func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences { preferences.current }

    /// 幂等取消。Esc、再按截图键、app 失焦、采集报错都收敛到这里。
    /// 即使状态机拒绝了这个迁移也强制收窗：卡住比丢掉一张截图严重得多。
    public func cancelSession() {
        let before = reducer.phase
        run(.commitRequested(.cancel))
        if reducer.phase == before {
            closeOverlay()
            reducer = MSSessionReducer()
            restoreFocus()
        }
        let afterPhase = reducer.phase.rawValue
        MSLog.info(.session, "cancelled from \(before.rawValue), now \(afterPhase)")
    }

    public var overlayVisible: Bool { overlay != nil }

    private func closeOverlay() {
        guard overlay != nil else { return }
        overlay?.teardown()
        overlay?.orderOut(nil)
        overlay?.contentView = nil
        overlay = nil
        // 这里**不**清 frozenFrame：它属于会话，不属于遮罩窗。
        // 以前关窗就清，而 `overlay(_:didRequest:)` 是先 `run(.commitRequested)`（ effects 里有关窗）
        // 再 `commit()`，于是 Enter/⌘C 走到 commit 时帧已经没了——整条提交出口静默空转（`E-063`）。
        // 释放点挪到会话真正回到 idle 的那一刻，见 `run(_:)`。
    }

    // MARK: - MSPinDelegate

    public func pinDidRequestCopy(_ pin: MSPinWindow) {
        guard let image = pin.pinView.bakedImage() else { return }
        let scale = Int((pin.screen?.backingScaleFactor ?? 2).rounded())
        let ok = clipboard.write(image, scale: scale)
        onToast?(ok ? "已复制贴图（\(image.width)×\(image.height)）" : "剪贴板写入失败")
    }

    public func pinDidRequestQuickSave(_ pin: MSPinWindow) {
        guard let image = pin.pinView.bakedImage() else { return }
        let scale = Int((pin.screen?.backingScaleFactor ?? 2).rounded())
        let req = MSExportRequest(image: image, scale: scale, format: preferences.current.export.format,
                                  jpegQuality: preferences.current.export.jpegQuality,
                                  naming: MSNamingTemplate(preferences.current.export.namingTemplate),
                                  directory: exportDirectory())
        switch fileExporter.save(req) {
        case .written(let path, _): onToast?("已保存 \(URL(fileURLWithPath: path).lastPathComponent)")
        case .failed(let e): onToast?("保存失败：\(e)")
        }
    }

    public func pinDidRequestToggleEdit(_ pin: MSPinWindow) {}
    public func pinDidBecomeIdle(_ pin: MSPinWindow) {}

    public func closeAllPins() { pins.closeAll() }
    public var pinCount: Int { pins.count }

    // MARK: - effects

    /// 没有 `default`：新增 effect 却忘了在这里交代，就编译不过。
    /// B-018：`default: break` 曾把 `.closeOverlay` 静默吞掉 → 遮罩不收、整屏吃点击，
    /// 看起来像整机卡死，只能杀进程。
    private func perform(_ effect: MSSessionEffect) {
        switch effect {
        case .closeOverlay:       closeOverlay()
        case .restoreFocus:       restoreFocus()
        case .showPermissionGate: onNeedsPermission?()
        case .toast(let text):    onToast?(text)
        case .copyColorText(let text):
            let ok = clipboard.writeText(text)
            onToast?(ok ? "已复制 \(text)" : "剪贴板写入失败")

        case .warnClearAnnotations: onToast?(MSSessionCopy.annotationCleared)
        case .log(let message):   MSLog.info(.session, message)
        // 下面这些由 startSnip()/commit() 的执行流落地，显式声明归属而不是静默丢弃。
        case .freeze, .showOverlay:
            MSLog.debug(.session, "effect handled by start flow: \(effect)")
        case .bakeAndCopy, .openPin, .saveToFile:
            MSLog.debug(.session, "effect handled by commit flow: \(effect)")
        }
    }

    /// Q-15 temporary default A: the overlay may take key focus, so the previous app is handed
    /// focus back when the session ends (`FR-SESS-003`).
    private func restoreFocus() {
        guard let app = frontAppBeforeSession, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let ok = app.activate(options: [])
        MSLog.info(.session, "restoreFocus → \(app.localizedName ?? "?") ok=\(ok)")
        frontAppBeforeSession = nil
    }

    private func pinMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制  ⌘C", action: #selector(MSPinView.menuCopy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "保存  ⌘S", action: #selector(MSPinView.menuQuickSave(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭贴图  ⌘W", action: #selector(MSPinView.menuClose(_:)), keyEquivalent: "")
        for item in menu.items { item.target = nil }   // first responder chain
        return menu
    }
}
