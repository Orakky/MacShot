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
    case log(String)
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
            return hasSelection ? [.log("selection \(w)x\(h)")] : [.log("selection too small")]

        case (.selecting, .drawBegan):
            guard hasSelection else { return [.toast("先框选区域")] }
            phase = .editing
            return []

        case (.editing, .drawEnded):
            hasElements = true
            phase = .selecting
            return [.log("element committed")]

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
            case .pin: return [.closeOverlay, .openPin, .restoreFocus]
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
            return [.closeOverlay, .restoreFocus, .toast("截图失败：\(reason)")]

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

    private var overlay: MSOverlayWindow?
    private var frozenFrame: MSCaptureFrame?
    private var displaySnapshot: [MSDisplay] = []
    private var activeDisplay: MSDisplay?
    private var frontAppBeforeSession: NSRunningApplication?

    public var onToast: ((String) -> Void)?
    public var onNeedsPermission: (() -> Void)?

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
    }

    private func startSnip() {
        guard reducer.phase == .idle else { MSLog.info(.session, "session busy, ignoring"); return }
        displaySnapshot = MSDisplayInventory.current()
        guard let display = MSDisplayInventory.display(under: NSEvent.mouseLocation, in: displaySnapshot) else {
            onToast?("找不到显示器"); return
        }
        activeDisplay = display
        frontAppBeforeSession = NSWorkspace.shared.frontmostApplication
        switch PermissionProbe.screenRecording() {
        case .denied:
            run(.permissionState(.denied))
            onNeedsPermission?()
            return
        default: break
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
                self.overlay = window
                window.present()
                self.run(.overlayShown)
            } catch {
                self.frozenFrame = nil
                self.run(.captureFailed(String(describing: error)))
                self.finishEffects()
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
        let doc = document ?? MSAnnotationDocument(canvasSize: cropped.pixelSize)
        guard let image = baker.bake(doc, source: cropped.image) ?? Optional(cropped.image) else { return }
        switch intent {
        case .copy, .savePanel, .quickSave:
            Task { @MainActor in
                let scale = Int(display.scale)
                switch intent {
                case .copy:
                    let ok = self.clipboard.write(image, scale: scale,
                                                  pngAndTiff: self.preferences.current.export.writesPngAndTiffToPasteboard)
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
                default: break
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

    public nonisolated func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {}

    public func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) {
        run(.commitRequested(intent))
        commit(intent: intent, selection: overlay.overlayView.globalSelection,
               document: overlay.overlayView.annotationDocument)
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

    private func closeOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
        frozenFrame = nil
    }

    // MARK: - MSPinDelegate

    public func pinDidRequestCopy(_ pin: MSPinWindow) {
        guard let image = pin.pinView.bakedImage() else { return }
        let scale = Int((pin.screen?.backingScaleFactor ?? 2).rounded())
        let ok = clipboard.write(image, scale: scale, pngAndTiff: preferences.current.export.writesPngAndTiffToPasteboard)
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

    private func perform(_ effect: MSSessionEffect) {
        switch effect {
        case .showPermissionGate: onNeedsPermission?()
        case .toast(let text): onToast?(text)
        case .restoreFocus: restoreFocus()
        case .log(let message): MSLog.info(.session, message)
        default: break
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
