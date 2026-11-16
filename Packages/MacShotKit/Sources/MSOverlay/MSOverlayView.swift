import AppKit
import CoreGraphics
import Foundation
import MSAnnotate
import MSCapture
import MSCore
import MSSettings

/// Keyboard-selectable tools. Letters follow `design/keymap.md` §3; `Q-03`'s 9 P0 tools minus
/// text/badge, which need a field editor and land with the toolbar pass.
public enum MSTool: String, CaseIterable, Sendable {
    case select, rect, ellipse, arrow, polyline, highlighter, pen, blur

    public var letter: String {
        switch self {
        case .select: "V"; case .rect: "R"; case .ellipse: "O"; case .arrow: "A"
        case .polyline: "L"; case .highlighter: "H"; case .pen: "P"; case .blur: "B"
        }
    }

    public var annotationKind: MSAnnotationKind? {
        switch self {
        case .select: nil
        case .rect: .rect
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .polyline: .polyline
        case .highlighter: .freehand
        case .pen: .freehand
        case .blur: .blur
        }
    }

    var isFreehandPen: Bool { self == .pen }
}

public protocol MSOverlayDelegate: AnyObject {
    func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?)
    func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent)
    func overlayDidCancel(_ overlay: MSOverlayWindow)
    /// Asks the session for the cropped pixels under a view-space rect (frozen frame, no re-capture).
    func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage?
    func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences
}

public final class MSOverlayWindow: NSWindow {
    public let overlayView: MSOverlayView
    public weak var overlayDelegate: MSOverlayDelegate?

    public init(display: MSDisplay, frame: CGImage) {
        overlayView = MSOverlayView(display: display, frozenFrame: frame)
        super.init(contentRect: display.logicalFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovable = false
        title = "MacShot Overlay"
        contentView = overlayView
        overlayView.host = self
        MSLog.info(.capture, "overlay shown frame=\(Int(display.logicalFrame.width))x\(Int(display.logicalFrame.height)) scale=\(display.scale)")
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public func present() {
        setFrame(displayFrame, display: false)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)      // Q-15 default A; see overlay-and-selection.md §2
        overlayView.needsDisplay = true
    }

    private var displayFrame: NSRect { frame }
}

/// Selection, annotation drawing, readout and the toolbar live here. View space is the display's
/// own AppKit space (y-up, 1 unit = 1 point).
public final class MSOverlayView: NSView {
    private let display: MSDisplay
    private let frozenFrame: CGImage
    private let renderer = MSAnnotationRenderer()
    weak var host: MSOverlayWindow?

    public private(set) var selection: CGRect?
    public var tool: MSTool = .select { didSet { needsDisplay = true } }
    public var colorHex: String = "#E83347"
    public var lineWidth: Int = 3
    public var blurRadius: Int = 14

    private var document: MSAnnotationDocument?
    private var history = MSAnnotationHistory()
    private var dragMode: DragMode?
    private var draft: MSAnnotationElement?
    private var cachedComposite: CGImage?

    private enum DragMode {
        case newSize(anchor: NSPoint)
        case move(grab: NSPoint, original: CGRect)
        case resize(handle: MSSelectionGeometry.Handle, original: CGRect)
        case draw(start: NSPoint)
    }

    private let palette = ["#E83347", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#AF52DE", "#000000", "#FFFFFF"]

    public init(display: MSDisplay, frozenFrame: CGImage) {
        self.display = display
        self.frozenFrame = frozenFrame
        super.init(frame: NSRect(origin: .zero, size: display.logicalFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not constructed from nib") }

    public override var isFlipped: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var delegate: MSOverlayDelegate? { host?.overlayDelegate }

    /// The selection in AppKit **global** logical coordinates — what the session crops with.
    public var globalSelection: CGRect? {
        guard let s = selection, let host else { return nil }
        return s.offsetBy(dx: host.frame.minX, dy: host.frame.minY)
    }

    public func setSelection(_ rect: CGRect?) {
        let previousSize = selection?.size
        selection = rect
        if let size = rect?.size, let previousSize, size != previousSize, document?.isEmpty == false {
            // Q-11 (temporary default): resizing the selection clears the annotations, with the
            // clear stated on screen rather than silently.
            document = MSAnnotationDocument(canvasSize: canvasSize(for: rect ?? .zero))
            history = MSAnnotationHistory()
            cachedComposite = nil
            MSLog.info(.overlay, "selection resized → annotations cleared (Q-11)")
        }
        if let rect { document = ensureDocument(for: rect) }
        cachedComposite = nil
        needsDisplay = true
        delegate?.overlay(host ?? MSOverlayWindow(display: display, frame: frozenFrame), selectionDidChange: rect)
    }

    private func canvasSize(for rect: CGRect) -> MSIntSize {
        guard let pixel = display.pixelRect(forLogical: globalRect(rect)) else { return .zero }
        return pixel.size
    }

    private func globalRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: host?.frame.minX ?? 0, dy: host?.frame.minY ?? 0)
    }

    private func ensureDocument(for rect: CGRect) -> MSAnnotationDocument {
        let size = canvasSize(for: rect)
        if let document, document.canvasSize == size { return document }
        return MSAnnotationDocument(canvasSize: size)
    }

    // MARK: - drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.draw(frozenFrame, in: bounds)

        if let sel = selection {
            ctx.saveGState()
            ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, 0.45).cgColor)
            // Four bands instead of an even-odd hole: only the changed band repaints.
            [CGRect(x: 0, y: 0, width: bounds.width, height: sel.minY),
             CGRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.maxY - sel.maxY),
             CGRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height),
             CGRect(x: sel.maxX, y: sel.minY, width: bounds.maxX - sel.maxX, height: sel.height)].forEach {
                ctx.fill($0)
             }
            ctx.restoreGState()
            drawSelectionContents(sel, in: ctx)
            drawHandles(sel, in: ctx)
            drawReadout(sel, in: ctx)
            drawToolbar(sel, in: ctx)
        } else {
            ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, 0.35).cgColor)
            ctx.fill(bounds)
            drawHint(in: ctx)
        }
    }

    /// Inside the selection we show the composited (bitmap + annotations) crop at 1:1 device
    /// pixels, so what you see is byte-for-byte what export produces (`NFR-011`).
    private func drawSelectionContents(_ sel: CGRect, in ctx: CGContext) {
        guard sel.width > 1, sel.height > 1 else { return }
        let composite = compositedCrop(for: sel)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        if let composite { ctx.draw(composite, in: sel) }
        else if let cropped = croppedSource(for: sel) { ctx.draw(cropped, in: sel) }
        ctx.restoreGState()
    }

    private func compositedCrop(for sel: CGRect) -> CGImage? {
        guard let document, !document.elements.isEmpty, let source = croppedSource(for: sel) else { return nil }
        if let cachedComposite, cachedElements == document.elements, cachedSourceSize == source.width * 1_000_000 + source.height {
            return cachedComposite
        }
        let image = renderer.render(document, source: source, intent: .preview)
        cachedComposite = image
        cachedElements = document.elements
        cachedSourceSize = source.width * 1_000_000 + source.height
        return image
    }

    private var cachedElements: [MSAnnotationElement] = []
    private var cachedSourceSize = 0

    private func croppedSource(for sel: CGRect) -> CGImage? {
        guard let pixel = display.pixelRect(forLogical: globalRect(sel)) else { return nil }
        // The frozen frame is the whole display, so pixel coords are already frame-local.
        return frozenFrame.cropping(to: pixel.cgRect)
    }

    private func drawSelectionBorder(_ sel: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(MSColorRGBA.rgba(255, 255, 255, 0.9).cgColor)
        ctx.setLineWidth(1); ctx.stroke(sel.insetBy(dx: 0.5, dy: 0.5))
        ctx.setStrokeColor(MSColorRGBA.rgba(0, 0, 0, 0.55).cgColor)
        ctx.stroke(sel.insetBy(dx: 1.5, dy: 1.5))
        ctx.restoreGState()
    }

    private func drawHandles(_ sel: CGRect, in ctx: CGContext) {
        drawSelectionBorder(sel, in: ctx)
        ctx.saveGState()
        ctx.setFillColor(MSColorRGBA.rgb(255, 255, 255).cgColor)
        ctx.setStrokeColor(MSColorRGBA.rgb(10, 132, 255).cgColor)
        ctx.setLineWidth(1)
        for p in handlePoints(of: sel) {
            let r = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
        }
        ctx.restoreGState()
    }

    private func handlePoints(of sel: CGRect) -> [CGPoint] {
        [CGPoint(x: sel.minX, y: sel.minY), CGPoint(x: sel.midX, y: sel.minY), CGPoint(x: sel.maxX, y: sel.minY),
         CGPoint(x: sel.maxX, y: sel.midY), CGPoint(x: sel.maxX, y: sel.maxY), CGPoint(x: sel.midX, y: sel.maxY),
         CGPoint(x: sel.minX, y: sel.maxY), CGPoint(x: sel.minX, y: sel.midY)]
    }

    private func drawReadout(_ sel: CGRect, in ctx: CGContext) {
        guard let pixel = display.pixelRect(forLogical: globalRect(sel)) else { return }
        var text = "\(pixel.width)×\(pixel.height)"
        if display.scale != 1 { text += " @\(Int(display.scale))x" }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.62),
        ]
        let s = NSAttributedString(string: " " + text + " ", attributes: attrs)
        let size = s.size()
        let below = sel.minY - size.height - 8 >= 0
        let p = NSPoint(x: min(max(0, sel.maxX - size.width), bounds.maxX - size.width),
                        y: below ? sel.minY - size.height - 8 : sel.maxY + 8)
        s.draw(at: p)
    }

    private func drawHint(in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.62),
        ]
        NSAttributedString(string: " 拖拽框选 · Enter 贴出 · ⌘C 复制 · Esc 取消 ",
                           attributes: attrs).draw(at: NSPoint(x: bounds.midX - 130, y: bounds.midY))
    }

    // MARK: - toolbar (compact; tool letters are the primary path)

    private var toolbarRect: CGRect?

    private func drawToolbar(_ sel: CGRect, in ctx: CGContext) {
        let item: CGFloat = 26, gap: CGFloat = 2
        let tools = MSTool.allCases
        let width = CGFloat(tools.count) * (item + gap) + 6 * 18 + 250
        let height: CGFloat = 34
        var rect = CGRect(x: sel.minX, y: sel.minY - height - 6, width: min(width, bounds.width - 12), height: height)
        if rect.minY < 4 { rect.origin.y = sel.maxY + 6 }
        toolbarRect = rect

        ctx.saveGState()
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor); ctx.strokePath()

        var x = rect.minX + 4
        for t in tools {
            let box = CGRect(x: x, y: rect.minY + 4, width: item, height: item)
            x += item + gap
            if box.maxX > rect.maxX - 250 { break }
            if t == tool {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor)
                ctx.fill(box)
            }
            NSAttributedString(string: t.letter, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
            ]).draw(at: NSPoint(x: box.midX - 4, y: box.midY - 8))
        }
        var cx = x + 8
        for hex in palette.prefix(6) {
            let box = CGRect(x: cx, y: rect.midY - 7, width: 14, height: 14)
            cx += 18
            guard box.maxX < rect.maxX - 250 else { break }
            ctx.setFillColor(NSColor(hex: hex)?.cgColor ?? NSColor.red.cgColor)
            ctx.fillEllipse(in: box)
            if hex == colorHex {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: box.insetBy(dx: -2, dy: -2))
            }
        }
        NSAttributedString(string: "Enter 贴出  ⌘C 复制  ⌘S 保存  Esc 取消", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]).draw(at: NSPoint(x: rect.maxX - 240, y: rect.midY - 7))
        ctx.restoreGState()
    }

    private func hitToolbar(_ p: NSPoint) -> Bool {
        guard let r = toolbarRect, r.contains(p) else { return false }
        let item: CGFloat = 26, gap: CGFloat = 2
        var x = r.minX + 4
        for t in MSTool.allCases {
            let box = CGRect(x: x, y: r.minY + 4, width: item, height: item)
            x += item + gap
            if box.contains(p) { tool = t; return true }
        }
        var cx = r.minX + CGFloat(MSTool.allCases.count) * (item + gap) + 12
        for hex in palette.prefix(6) {
            let box = CGRect(x: cx, y: r.midY - 7, width: 14, height: 14)
            cx += 18
            if box.insetBy(dx: -3, dy: -3).contains(p) { colorHex = hex; return true }
        }
        return true
    }

    // MARK: - mouse

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard !hitToolbar(p) else { needsDisplay = true; return }
        if let tool = tool.annotationKind, let sel = selection, sel.contains(p) {
            dragMode = .draw(start: p)
            draft = MSAnnotationElement(kind: tool, points: [docPoint(p, in: sel), docPoint(p, in: sel)],
                                        style: currentStyle(), variant: tool == .freehand && self.tool.isFreehandPen ? "pen" : nil)
            return
        }
        if let sel = selection {
            let h = MSSelectionGeometry.handle(at: p, of: sel)
            switch h {
            case .body: dragMode = .move(grab: p, original: sel)
            case .none: dragMode = .newSize(anchor: p); setSelection(CGRect(origin: p, size: .zero))
            default: dragMode = .resize(handle: h, original: sel)
            }
        } else {
            dragMode = .newSize(anchor: p)
            setSelection(CGRect(origin: p, size: .zero))
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .newSize(let anchor):
            var rect = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y),
                              width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
            if event.modifierFlags.contains(.option) {
                let side = max(rect.width, rect.height)
                if p.x < anchor.x { rect.origin.x = anchor.x - side }
                if p.y < anchor.y { rect.origin.y = anchor.y - side }
                rect.size = CGSize(width: side, height: side)
            }
            setSelection(rect)
        case .move(let grab, let original):
            setSelection(original.offsetBy(dx: p.x - grab.x, dy: p.y - grab.y))
        case .resize(let handle, let original):
            let t = CGSize(width: p.x - (handle == .left || handle == .topLeft || handle == .bottomLeft ? original.minX : original.maxX),
                           height: p.y - (handle == .bottom || handle == .bottomLeft || handle == .bottomRight ? original.minY : original.maxY))
            let next = MSSelectionGeometry.resized(by: translation(for: handle, from: original, to: p), handle: handle,
                                                   from: original, clampTo: bounds)
            _ = t
            setSelection(next)
        case .draw(let start):
            guard var d = draft, let sel = selection else { return }
            let dp = docPoint(p, in: sel)
            if d.kind.takesFreehandPoints {
                if let last = d.points.last, abs(last.x - dp.x) + abs(last.y - dp.y) > 2 { d.points.append(dp) }
            } else {
                d.points = [d.points[0], dp]
            }
            _ = start
            draft = d
            needsDisplay = true
        case nil: break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        defer { dragMode = nil }
        guard let d = draft else {
            if let sel = selection, sel.width < 4 || sel.height < 4 { setSelection(nil) }
            return
        }
        draft = nil
        let sizable = MSAnnotationGeometry.bounds(of: d).map { $0.width > 2 || $0.height > 2 } ?? false
        if d.kind != .rect || sizable {
            if var doc = document {
                history.apply(.insert(d), to: &doc)
                document = doc
                cachedComposite = nil
            }
        }
        needsDisplay = true
    }

    /// View point (y-up) → canvas pixel of the current selection (y-down).
    private func docPoint(_ p: NSPoint, in sel: CGRect) -> MSIntPoint {
        let s = display.scale
        let x = (p.x - sel.minX) * s
        let y = (sel.maxY - p.y) * s
        return MSIntPoint(x: Int(x.rounded()), y: Int(y.rounded()))
    }

    private func translation(for handle: MSSelectionGeometry.Handle, from original: CGRect, to p: NSPoint) -> CGSize {
        switch handle {
        case .left: CGSize(width: p.x - original.minX, height: 0)
        case .right: CGSize(width: p.x - original.maxX, height: 0)
        case .top: CGSize(width: 0, height: p.y - original.maxY)
        case .bottom: CGSize(width: 0, height: p.y - original.minY)
        case .topLeft: CGSize(width: p.x - original.minX, height: p.y - original.maxY)
        case .topRight: CGSize(width: p.x - original.maxX, height: p.y - original.maxY)
        case .bottomLeft: CGSize(width: p.x - original.minX, height: p.y - original.minY)
        case .bottomRight: CGSize(width: p.x - original.maxX, height: p.y - original.minY)
        case .body, .none: .zero
        }
    }

    private func currentStyle() -> MSAnnotationStyle {
        var s = MSAnnotationStyle(stroke: MSColorRGBA(hex: colorHex) ?? .rgb(232, 51, 71), lineWidth: lineWidth)
        s.blurRadius = blurRadius
        if tool == .highlighter { s.fill = nil }
        return s
    }

    // MARK: - keyboard

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: delegate?.overlayDidCancel(host!)                       // Esc
        case 36, 76:                                                       // Enter
            commit(defaultIntent(from: delegate?.overlayPreferences(host!)))
        case 8:                                                            // C
            if flags.contains(.command) { delegate?.overlay(host!, didRequest: .copy) }
        case 35:                                                            // P
            if flags.contains(.command) { delegate?.overlay(host!, didRequest: .pin) }
        case 1:                                                             // S
            if flags.contains(.command) {
                delegate?.overlay(host!, didRequest: flags.contains(.shift) ? .quickSave : .savePanel)
            }
        case 49 where flags.contains(.option):                             // Space+⌥ toggles nothing; placeholder
            break
        case 6 where flags.contains(.command):                             // ⌘Z
            if flags.contains(.shift) { redo() } else { undo() }
        case 51, 117:                                                      // Delete / Backspace
            deleteSelectedOrLast()
        default:
            if let t = MSTool.allCases.first(where: { $0.letter.lowercased() == event.charactersIgnoringModifiers?.lowercased() }),
               !flags.contains(.command) {
                tool = t
            } else if event.charactersIgnoringModifiers?.lowercased() == "]" {
                lineWidth = min(12, lineWidth + 1); needsDisplay = true
            } else if event.charactersIgnoringModifiers?.lowercased() == "[" {
                lineWidth = max(1, lineWidth - 1); needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func defaultIntent(from prefs: MSAppPreferences?) -> MSCommitIntent {
        switch prefs?.commitBehavior ?? .pin {
        case .pin: .pin
        case .copy: .copy
        case .save: .savePanel
        }
    }

    private func commit(_ intent: MSCommitIntent) {
        if selection == nil { NSSound.beep(); return }
        delegate?.overlay(host!, didRequest: intent)
    }

    public func undo() {
        guard var doc = document, history.undo(&doc) else { return }
        document = doc; cachedComposite = nil; needsDisplay = true
    }

    public func redo() {
        guard var doc = document, history.redo(&doc) else { return }
        document = doc; cachedComposite = nil; needsDisplay = true
    }

    private func deleteSelectedOrLast() {
        guard var doc = document, let last = doc.elements.max(by: { $0.z < $1.z }) else { return }
        history.apply(.remove(last), to: &doc)
        document = doc; cachedComposite = nil; needsDisplay = true
    }

    /// The document the session exports. Empty document when nothing was drawn (still a valid
    /// crop, so copy/pin work with zero annotations).
    public var annotationDocument: MSAnnotationDocument {
        document ?? MSAnnotationDocument(canvasSize: selection.flatMap { canvasSize(for: $0) } ?? .zero)
    }

    public var currentTool: MSTool { tool }
}

extension NSColor {
    convenience init?(hex: String) {
        guard let c = MSColorRGBA(hex: hex) else { return nil }
        self.init(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: CGFloat(c.alpha))
    }
}
