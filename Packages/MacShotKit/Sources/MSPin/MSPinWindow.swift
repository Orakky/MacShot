import AppKit
import CoreGraphics
import Foundation
import MSAnnotate
import MSCore
import MSSettings

/// What a pin holds. `.document` is the D-04 path; a foreign bitmap is wrapped into an empty
/// document immediately so there is exactly one rendering path (`pin-window.md` §2).
public struct MSPinContent: Sendable {
    public var document: MSAnnotationDocument
    public var source: CGImage
    public var scale: Int
    /// Where the crop came from, for the badge and future re-export.
    public var sourcePixelRect: MSIntRect?

    public init(document: MSAnnotationDocument, source: CGImage, scale: Int, sourcePixelRect: MSIntRect? = nil) {
        self.document = document; self.source = source; self.scale = scale; self.sourcePixelRect = sourcePixelRect
    }

    public static func bitmap(_ image: CGImage, scale: Int) -> MSPinContent {
        let size = MSIntSize(width: image.width, height: image.height)
        return MSPinContent(document: MSAnnotationDocument(canvasSize: size), source: image, scale: max(1, scale))
    }

    public var logicalSize: CGSize {
        CGSize(width: CGFloat(document.canvasSize.width) / CGFloat(scale),
               height: CGFloat(document.canvasSize.height) / CGFloat(scale))
    }
}

/// Level candidates for `ADR-019`. Ascending order is a fact about AppKit, not a preference:
/// floating(3) < modalPanel(8) < dock(20) < mainMenu(24) < statusBar(25) < popUpMenu(101) < screenSaver(1000).
public enum MSPinLevel: String, Sendable, CaseIterable {
    case floating, statusBar, statusBarPlusOne, popUpMenu

    public var value: NSWindow.Level {
        switch self {
        case .floating: .floating
        case .statusBar: .statusBar
        case .statusBarPlusOne: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        case .popUpMenu: .popUpMenu
        }
    }

    /// Measured choice goes here; until then `.statusBar` plus `.fullScreenAuxiliary`
    /// (`pin-window.md` §1: the behaviour attribute does most of the work, not the number).
    public static let current: MSPinLevel = .statusBar
}

public protocol MSPinDelegate: AnyObject {
    func pinDidRequestCopy(_ pin: MSPinWindow)
    func pinDidRequestQuickSave(_ pin: MSPinWindow)
    func pinDidRequestToggleEdit(_ pin: MSPinWindow)
    func pinDidBecomeIdle(_ pin: MSPinWindow)
}

public final class MSPinWindow: NSPanel {
    public let pinView: MSPinView
    public let id = UUID()
    public weak var pinDelegate: MSPinDelegate?
    /// Exported (copied/saved) at least once since the last edit — drives the "未导出" badge.
    public var hasExported: Bool = true

    public init(content: MSPinContent, origin: NSPoint?, menu: NSMenu?) {
        let size = content.logicalSize
        pinView = MSPinView(content: content)
        super.init(contentRect: NSRect(origin: origin ?? .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = MSPinLevel.current.value
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        title = "MacShot Pin"
        contentView = pinView
        pinView.menuProvider = { menu }
        pinView.onAction = { [weak self] action in self?.handle(action) }
        setContentSize(size)
        MSLog.info(.pin, "pin id=\(self.id.uuidString.prefix(8)) px=\(content.document.canvasSize.width)x\(content.document.canvasSize.height) scale=\(content.scale) level=\(MSPinLevel.current.rawValue)")
    }

    public override var canBecomeKey: Bool { true }        // edit state needs a text field
    public override var canBecomeMain: Bool { false }

    private func handle(_ action: MSPinView.Action) {
        switch action {
        case .copy: hasExported = true; pinDelegate?.pinDidRequestCopy(self)
        case .quickSave: hasExported = true; pinDelegate?.pinDidRequestQuickSave(self)
        case .toggleEdit: pinDidRequestToggleEdit()
        case .close: close()
        }
    }

    private func pinDidRequestToggleEdit() {
        pinView.isEditing.toggle()
        isMovableByWindowBackground = !pinView.isEditing      // drag-window vs drag-annotation (`pin-window.md` §4`)
        markDirty()
        pinDelegate?.pinDidRequestToggleEdit(self)
        MSLog.info(.pin, "edit=\(self.pinView.isEditing) movableByBackground=\(self.isMovableByWindowBackground)")
    }

    /// Any edit makes the pin "unsaved" again, so the badge tells the truth about loss risk.
    public func markDirty() { hasExported = false; pinView.needsDisplay = true }

    public func center(on screen: NSScreen?, display: Bool) {
        guard let screen else { return }
        let f = frame
        let origin = NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.midY - f.height / 2)
        setFrameOrigin(NSPoint(x: max(screen.visibleFrame.minX, origin.x), y: max(screen.visibleFrame.minY, origin.y)))
        orderFrontRegardless()
    }

    public func resetOrigin(for screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        var f = frame
        if !visible.intersects(f) {
            f.origin = NSPoint(x: visible.midX - f.width / 2, y: visible.midY - f.height / 2)
            setFrame(f, display: true)
            MSLog.info(.pin, "pin moved back on screen change")
        }
    }
}

/// Draws the bitmap scaled, and the vector layer redrawn at display resolution: zoom > 1 shows
/// pixel blocks in the image but crisp strokes — the visible proof of `D-04` (`FR-PIN-003`).
public final class MSPinView: NSView {
    public enum Action: Sendable { case copy, quickSave, toggleEdit, close }

    public var content: MSPinContent
    public var history = MSAnnotationHistory()
    public var isEditing = false { didSet { needsDisplay = true } }
    public var zoom: CGFloat = 1 { didSet { resizeWindow(); needsDisplay = true } }
    public var opacityValue: CGFloat = 1 { didSet { window?.alphaValue = opacityValue; needsDisplay = true } }
    public var selectedElementID: UUID?

    var onAction: ((Action) -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let renderer = MSAnnotationRenderer()
    private var draft: MSAnnotationElement?
    private var dragStart: NSPoint?

    public init(content: MSPinContent) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: content.logicalSize.width, height: content.logicalSize.height)))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not constructed from nib") }

    public override var isFlipped: Bool { false }   // y-up, so renderElements' own flip is correct
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func resizeWindow() {
        guard let window else { return }
        let size = CGSize(width: content.logicalSize.width * zoom, height: content.logicalSize.height * zoom)
        var f = window.frame
        let dy = size.height - f.height
        f.origin.y -= dy                                   // keep the top edge put while zooming
        f.size = size
        window.setFrame(f, display: true, animate: false)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let docSize = content.document.canvasSize
        let docW = CGFloat(max(1, docSize.width))

        // 1) bitmap: above 100% we want visible pixel squares, not smoothing (`FR-PIN-003`).
        ctx.saveGState()
        ctx.interpolationQuality = zoom > 1 ? .none : .medium
        ctx.draw(content.source, in: bounds)
        ctx.restoreGState()

        // 2) vector layer: one unit = one canvas pixel, scaled up to the view. AppKit's context is
        //    already in backing-store pixels, so strokes stay crisp at any zoom.
        ctx.saveGState()
        ctx.scaleBy(x: bounds.width / docW, y: bounds.width / docW)
        renderer.renderElements(of: content.document, into: ctx, source: content.source,
                               canvas: docSize, intent: .pin)
        if let draft { renderer.renderElements(of: draftDocument(draft), into: ctx, source: content.source,
                                              canvas: docSize, intent: .preview) }
        ctx.restoreGState()

        if isEditing { drawEditModeChrome() }
        drawBadge()
    }

    private func draftDocument(_ element: MSAnnotationElement) -> MSAnnotationDocument {
        var doc = content.document
        doc.elements = [element]
        return doc
    }

    private func drawEditModeChrome() {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1; p.stroke()
    }

    private func drawBadge() {
        var parts: [String] = []
        if abs(zoom - 1) > 0.001 { parts.append("\(Int((zoom * 100).rounded()))%") }
        if opacityValue < 0.999 { parts.append("\(Int((opacityValue * 100).rounded()))%") }
        if !hasExportedFlag { parts.append("未导出") }
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: " ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.62),
        ]
        let s = NSAttributedString(string: " " + text + " ", attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: bounds.maxX - size.width - 6, y: bounds.maxY - size.height - 6))
    }

    private var hasExportedFlag: Bool { window is MSPinWindow ? (window as? MSPinWindow)?.hasExported ?? true : true }

    // MARK: - editing (same document object, not a copy)

    /// Tool chosen in the shared toolbar; nil means "selection tool" (drag moves the window).
    public var activeTool: MSAnnotationKind?

    public override func mouseDown(with event: NSEvent) {
        guard isEditing, let tool = activeTool, tool != .eraser else { super.mouseDown(with: event); return }
        let p = docPoint(convert(event.locationInWindow, from: nil))
        if tool == .eraser { eraseAt(viewPoint: event.locationInWindow); return }
        draft = MSAnnotationElement(kind: tool, points: [p, p], style: content.document.currentStyle,
                                   text: tool == .badge ? content.document.nextBadgeText : "",
                                   variant: tool == .freehand ? "pen" : nil)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isEditing, draft != nil else { super.mouseDragged(with: event); return }
        let p = docPoint(convert(event.locationInWindow, from: nil))
        guard var d = draft else { return }
        if d.kind.takesFreehandPoints {
            if let last = d.points.last, hypot(Double(p.x - last.x), Double(p.y - last.y)) > 2 { d.points.append(p) }
        } else {
            d.points = [d.points[0], p]
        }
        draft = d
        (window as? MSPinWindow)?.hasExported = false
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEditing, let d = draft else { super.mouseUp(with: event); return }
        draft = nil
        let sizable = MSAnnotationGeometry.bounds(of: d).map { $0.width > 3 || $0.height > 3 } ?? false
        if d.kind.isTextual || sizable {
            history.apply(.insert(d), to: &content.document)
            if d.kind == .badge { content.document.advanceBadge() }
            (window as? MSPinWindow)?.markDirty()
        }
        needsDisplay = true
    }

    private func eraseAt(viewPoint: NSPoint) {
        let p = docPoint(convert(viewPoint, from: nil))
        let target = CGPoint(x: p.x, y: p.y)
        guard let hit = content.document.sortedElements.reversed().first(where: {
            MSAnnotationGeometry.hitTest(target, element: $0)
        }) else { return }
        history.apply(.remove(hit), to: &content.document)
        (window as? MSPinWindow)?.markDirty()
        needsDisplay = true
    }

    public func undoEdit() {
        if history.undo(&content.document) { (window as? MSPinWindow)?.markDirty(); needsDisplay = true }
    }

    public func bakedImage() -> CGImage? {
        renderer.render(content.document, source: content.source, intent: .export)
    }

    /// View point (y-up) → canvas pixel (y-down): the one conversion in this view.
    private func docPoint(_ p: NSPoint) -> MSIntPoint {
        let doc = content.document.canvasSize
        let x = p.x / max(1, bounds.width) * CGFloat(doc.width)
        let y = (bounds.height - p.y) / max(1, bounds.height) * CGFloat(doc.height)
        return MSIntPoint(x: Int(x.rounded()), y: Int(y.rounded()))
    }

    private func setZoom(_ next: CGFloat, around pointer: NSPoint? = nil) {
        let clamped = min(8, max(0.05, next))
        guard clamped != zoom else { return }
        zoom = clamped
    }

    public override func scrollWheel(with event: NSEvent) {
        let step: CGFloat = event.deltaY > 0 ? 1.1 : (event.deltaY < 0 ? 1 / 1.1 : 1)
        if event.modifierFlags.contains(.command) {
            opacityValue = min(1, max(0.05, opacityValue + (event.deltaY > 0 ? 0.05 : -0.05)))
        } else {
            setZoom(zoom * step, around: convert(event.locationInWindow, from: nil))
        }
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c" where flags.contains(.command): onAction?(.copy)
        case "s" where flags.contains(.command): onAction?(.quickSave)
        case "w" where flags.contains(.command): onAction?(.close)
        case "e" where flags.isDisjoint(with: [.command, .control]): onAction?(.toggleEdit)
        case "z" where flags.contains(.command): undoEdit()
        case "0" where flags.contains(.command): opacityValue = 1; window?.alphaValue = 1; needsDisplay = true
        default: super.keyDown(with: event)
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    @objc public func menuCopy(_ sender: Any?) { onAction?(.copy) }
    @objc public func menuQuickSave(_ sender: Any?) { onAction?(.quickSave) }
    @objc public func menuToggleEdit(_ sender: Any?) { onAction?(.toggleEdit) }
    @objc public func menuClose(_ sender: Any?) { onAction?(.close) }
}

/// Tracks live pins so the menu can close them all (`FR-SET-001`).
public final class MSPinRegistry: @unchecked Sendable {
    private var pins: [MSPinWindow] = []
    private var observers: [NSObjectProtocol] = []
    private let lock = NSLock()

    public init() {}

    public var count: Int { lock.withLock { pins.count } }
    public var all: [MSPinWindow] { lock.withLock { pins } }

    @discardableResult
    public func open(_ content: MSPinContent, near screenPoint: NSPoint?, level: NSWindow.Level = MSPinLevel.current.value,
                     menu: NSMenu?, onClose: @escaping (MSPinWindow) -> Void = { _ in }) -> MSPinWindow {
        let pin = MSPinWindow(content: content, origin: screenPoint, menu: menu)
        pin.level = level
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                          object: pin, queue: .main) { [weak self] _ in
            self?.remove(pin)
            onClose(pin)
        }
        lock.withLock { pins.append(pin); observers.append(token) }
        pin.orderFrontRegardless()
        MSLog.info(.pin, "open count=\(self.count)")
        return pin
    }

    private func remove(_ pin: MSPinWindow) {
        lock.withLock { pins.removeAll { $0 === pin } }
        MSLog.info(.pin, "closed, remaining=\(self.count)")
    }

    public func closeAll(askUser: Bool = false) {
        let list = lock.withLock { pins }
        for pin in list { pin.close() }
        lock.withLock { pins.removeAll() }
        MSLog.info(.pin, "closed all (\(list.count))")
        _ = askUser
    }

    /// Bring a pin back on-screen after a display change (`pin-window.md` §9).
    public func reanchorAll(to screen: NSScreen?) {
        all.forEach { $0.resetOrigin(for: screen) }
    }
}
