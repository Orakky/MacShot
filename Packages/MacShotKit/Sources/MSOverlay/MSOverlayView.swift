import AppKit
import CoreGraphics
import Foundation
import MSAnnotate
import MSCapture
import MSCore
import MSSettings

/// 遮罩上"看得见、点得到"的固定控件。命中区永远比视觉区大（`hit.min` 规范）。
public enum OverlayChrome {
    public static let cancelVisual: CGFloat = 28
    public static let cancelHit: CGFloat = 44
    public static let margin: CGFloat = 14

    /// 左上角取消按钮的**命中区**（视图坐标，y 向上 → 左上即 maxY 一侧）。
    public static func cancelHitRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + margin, y: bounds.maxY - cancelHit - margin,
               width: cancelHit, height: cancelHit)
    }

    public static func cancelVisualRect(in bounds: CGRect) -> CGRect {
        let hit = cancelHitRect(in: bounds)
        let inset = (cancelHit - cancelVisual) / 2
        return hit.insetBy(dx: inset, dy: inset)
    }

    /// 绘制用的矩形：与命中区**同一个坐标空间**（`draw(_:)` 的 CTM 不做额外翻转，实测冻结帧在这种
    /// 上下文里是正着画出来的）。视图里不许再自己算一次 y —— 11-16 实拍就是多翻了一次，
    /// 结果"看得见的 ✕"在左下、"点得到的 ✕"在左上，鼠标那条退出路径等于没有。
    public static func cancelPaintRect(in bounds: CGRect) -> CGRect { cancelVisualRect(in: bounds) }

    /// 与 ✕ 同一处的文字提示条左上锚点（跟着 ✕ 走，不单独定位）。
    public static func cancelHintOrigin(in bounds: CGRect) -> CGPoint {
        let paint = cancelPaintRect(in: bounds)
        return CGPoint(x: paint.maxX + 10, y: paint.midY - 9)
    }

    /// 遮罩暗化层 alpha —— 数值真源是 `design/design-system.md` §2.1 的 `overlay.scrim`
    /// （浅色 45%、深色 55%），不随"有没有选区"变化。此前实现自造了 0.35/0.45 两个值，属规格外。
    public static func scrimAlpha(isDark: Bool) -> CGFloat { isDark ? 0.55 : 0.45 }
}


/// 标注绘制的阶段。穷举，不许用 `default` 吞掉（规范 §4b）。
public enum MSOverlayDrawingPhase: Sendable, Equatable {
    case began(MSAnnotationKind)
    case ended(elementCount: Int)
}

public protocol MSOverlayDelegate: AnyObject {
    func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?)
    func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent)
    func overlayDidCancel(_ overlay: MSOverlayWindow)
    /// 标注绘制的起止（`ST-001` 行 9/10）。会话靠它把 `selecting ⇄ editing` 走起来，
    /// 并在 `drawEnded` 后知道文档里已经有元素——行 7 的"改选区清空要提示"依赖这个事实。
    /// 此前 `drawBegan/drawEnded` 两个事件**没有任何生产者**，所以 `hasElements` 永远是 false。
    func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase)
    /// 元素层数量变了（提交/删除/撤销/清空）。`didSet` 自动报，不靠调用点记得。
    func overlay(_ overlay: MSOverlayWindow, elementCount: Int)
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

    private var keyMonitor: Any?
    private var escapeWatch: Any?

    /// 顺序很关键：先 activate，再 makeKey，再把焦点交给视图。
    /// app 未激活时设 key window 不生效，`keyDown` 就不会进来——11-16 那次"Esc 完全没反应"
    /// 是这个时序 + 视图从来不是 first responder 两件事叠在一起。
    public func present() {
        setFrame(displayFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)      // Q-15 临时默认档 A
        makeKeyAndOrderFront(nil)
        makeFirstResponder(overlayView)
        installKeyMonitor()
        overlayView.needsDisplay = true
        installEscapeWatch()
        claimKey(attempt: 0)
    }

    /// `NSApp.activate` 是异步的：只抢一次会停在 `isKeyWindow == false` 上，键事件进不来。
    /// 逐步重试并记日志，哪一次成功一目了然（16:13 的实测就是 key=false / responder=true）。
    private func claimKey(attempt: Int) {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(overlayView)
        let keyed = isKeyWindow
        let focused = firstResponder is MSOverlayView
        MSLog.info(.capture, "overlay claimKey#\(attempt) key=\(keyed) responder=\(focused)")
        if keyed { return }
        guard attempt < 6 else {
            MSLog.error(.capture, "overlay never became key window: 键盘不可用，只能靠 ✕/右键退出")
            return
        }
        let delays: [Double] = [0.03, 0.06, 0.12, 0.2, 0.3, 0.5]
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            self?.claimKey(attempt: attempt + 1)
        }
    }

    /// 最后一道保险：全局监听 `Esc`。它不消费事件，只在遮罩确实开着时收窗；
    /// 没有输入监控权限时不会触发，因此鼠标出路（✕ / 右键）仍是主兜底。
    private func installEscapeWatch() {
        guard escapeWatch == nil else { return }
        escapeWatch = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return }
            Task { @MainActor in
                guard self.isVisible, self.overlayView.window != nil else { return }
                MSLog.info(.capture, "global Esc watched → cancel")
                self.overlayView.cancelViaEscape()
            }
        }
    }

    /// 遮罩是否还摊在屏幕上（不叫 isVisible：那是 NSWindow 自己的属性名）。

    /// 本地监视器：responder 链断了也还能收到键，`Esc`/`Enter` 至少留一条通路。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.type == .keyDown,
                  let view = self.contentView as? MSOverlayView else { return event }
            return view.handleKey(event) ? nil : event
        }
    }

    /// 收窗前必须摘掉监视器，否则它会一直吃掉后续所有按键（B-022）。
    public func teardown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let escapeWatch { NSEvent.removeMonitor(escapeWatch) }
        escapeWatch = nil
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

    /// internal 而非 private：`@testable` 要直接喂文档、点一次动作、再看撤销栈（`AnnotationToolTests`）。
    /// internal：`@testable` 用它直接喂文档，测试因此不必靠合成鼠标事件构造状态。
    /// `didSet` 负责把元素数报给会话——9 个赋值点各自记得调一次迟早会漏，
    /// 而 `hasElements` 说一次谎，行 7 的清空提示就一次都不响。
    var document: MSAnnotationDocument? {
        didSet {
            guard document?.elements.count != oldValue?.elements.count else { return }
            reportElementCount()
        }
    }
    var history = MSAnnotationHistory()
    private var dragMode: DragMode?
    private var draft: MSAnnotationElement?
    private var cachedComposite: CGImage?

    private enum DragMode {
        case newSize(anchor: NSPoint)
        case move(grab: NSPoint, original: CGRect)
        case resize(handle: MSSelectionGeometry.Handle, original: CGRect)
        case draw(start: NSPoint)
        /// 拖动已选中的元素：`recorder` 把上百次 mouseDragged 收成一条撤销记录（`ADR-011`）
        case moveElement(recorder: MSDragRecorder, grab: MSIntPoint)
    }

    /// 选中的元素 id。`FR-ANN-004`：点元素选中、点空白取消、把手只在选中时出现。
    /// internal 是给 `@testable` 直接喂状态，不靠合成鼠标事件。
    var selectedID: UUID?

    private let palette = MSAnnotationPalette.swatches

    public init(display: MSDisplay, frozenFrame: CGImage) {
        self.display = display
        self.frozenFrame = frozenFrame
        super.init(frame: NSRect(origin: .zero, size: display.logicalFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not constructed from nib") }

    public override var isFlipped: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// NSView 默认不接受键盘焦点，borderless 窗也不会自动选人 ——
    /// 漏掉这两个 override 的后果是 `keyDown` 永不被调用，`Esc` 表现为"完全没反应"。
    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { true }

    var delegate: MSOverlayDelegate? { host?.overlayDelegate }

    /// The selection in AppKit **global** logical coordinates — what the session crops with.
    public var globalSelection: CGRect? {
        guard let s = selection, let host else { return nil }
        return s.offsetBy(dx: host.frame.minX, dy: host.frame.minY)
    }

    public func setSelection(_ rect: CGRect?) {
        let previousSize = selection?.size
        selection = rect
        // 顺序有讲究：先让会话知道"选区变了"（此时 `hasElements` 还是清空前的真值，
        // 行 7 才能提示），再真的换掉文档。反过来就永远不提示。
        if let size = rect?.size, let previousSize, size != previousSize, document?.isEmpty == false {
            host.map { delegate?.overlay($0, selectionDidChange: rect) }
        }
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
        let scrim = OverlayChrome.scrimAlpha(isDark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        if let sel = selection {
            ctx.saveGState()
            ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, scrim).cgColor)
            // Four bands instead of an even-odd hole: only the changed band repaints.
            [CGRect(x: 0, y: 0, width: bounds.width, height: sel.minY),
             CGRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.maxY - sel.maxY),
             CGRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height),
             CGRect(x: sel.maxX, y: sel.minY, width: bounds.maxX - sel.maxX, height: sel.height)].forEach {
                ctx.fill($0)
             }
            ctx.restoreGState()
            drawSelectionContents(sel, in: ctx)
            drawElementSelection(sel, in: ctx)
            drawHandles(sel, in: ctx)
            // 先算工具条再画读数：读数的落位要看工具条占没占外侧（同帧真值，不用上一帧的 layout）
            drawToolbar(sel, in: ctx)
            drawReadout(sel, in: ctx)
        } else {
            ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, scrim).cgColor)
            ctx.fill(bounds)
            drawHint(in: ctx)
        }
        drawCancelButton(in: ctx)
    }

    /// 常驻退出入口：左上角（不跟选区跑，任何时刻都在同一个位置，闭眼也能点到）。
    /// 位置全部问 `OverlayChrome` 要，这里不做任何坐标换算——画的位置必须就是点的位置。
    private func drawCancelButton(in ctx: CGContext) {
        let rect = OverlayChrome.cancelPaintRect(in: bounds)
        ctx.saveGState()
        ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, 0.55).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(MSColorRGBA.rgb(255, 255, 255).cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        let r = rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)
        ctx.move(to: r.origin); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.strokePath()
        ctx.restoreGState()
        NSAttributedString(string: "  Esc 或点此 ✕ 退出截图（右键也退出） ", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ]).draw(at: OverlayChrome.cancelHintOrigin(in: bounds))
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

    /// 选中元素的高亮框：`FR-ANN-004` 要求"点元素选中"要有可见反馈。
    /// 画在文档坐标里再随选区落位，尺寸取元素的几何 bounds（含线宽外溢）。
    private func drawElementSelection(_ sel: CGRect, in ctx: CGContext) {
        guard let id = selectedID, let element = document?.elements.first(where: { $0.id == id }),
              let box = MSAnnotationGeometry.bounds(of: element) else { return }
        let pad = 2
        let viewRect = CGRect(x: sel.minX + CGFloat(box.minX) / display.scale,
                              y: sel.maxY - CGFloat(box.maxY) / display.scale,
                              width: CGFloat(box.width) / display.scale,
                              height: CGFloat(box.height) / display.scale)
            .insetBy(dx: -CGFloat(pad), dy: -CGFloat(pad))
        ctx.saveGState()
        ctx.setStrokeColor(MSColorRGBA.rgb(10, 132, 255).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.stroke(viewRect)
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
        let p = MSOverlayToolbar.readoutOrigin(selection: sel, bounds: bounds,
                                              readoutSize: size, toolbar: toolbarLayout?.rect)
        s.draw(at: p)
    }

    private func drawHint(in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.62),
        ]
        NSAttributedString(string: " 拖拽框选 · Enter 贴出 · ⌘C 复制 · Esc / 点 ✕ / 右键 退出 ",
                           attributes: attrs).draw(at: NSPoint(x: bounds.midX - 178, y: bounds.midY))
    }

    // MARK: - toolbar (compact; tool letters are the primary path)

    private var toolbarLayout: MSOverlayToolbar.Layout?

    private func drawToolbar(_ sel: CGRect, in ctx: CGContext) {
        let layout = MSOverlayToolbar.layout(selection: sel, bounds: bounds,
                                            tools: MSTool.allCases, colors: Array(palette.prefix(6)))
        toolbarLayout = layout
        let rect = layout.rect
        ctx.saveGState()
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor); ctx.strokePath()

        for (t, box) in layout.toolBoxes {
            if t == tool {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor)
                ctx.fill(box)
            }
            NSAttributedString(string: t.letter, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
            ]).draw(at: NSPoint(x: box.midX - 4, y: box.midY - 8))
        }
        for (hex, box) in layout.colorBoxes {
            ctx.setFillColor(NSColor(hex: hex)?.cgColor ?? NSColor.red.cgColor)
            ctx.fillEllipse(in: box)
            if hex == colorHex {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: box.insetBy(dx: -2, dy: -2))
            }
        }
        if layout.showsActions {
            NSAttributedString(string: "Enter 贴出  ⌘C 复制  ⌘S 保存  Esc 取消", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            ]).draw(at: NSPoint(x: rect.maxX - 240, y: rect.midY - 7))
        }
        ctx.restoreGState()
    }

    /// 命中区直接取绘制用的同一份 layout：两处各算一遍就是 ✕ 那个 bug 的成因。
    private func hitToolbar(_ p: NSPoint) -> Bool {
        guard let layout = toolbarLayout, layout.rect.contains(p) else { return false }
        for (t, box) in layout.toolBoxes where box.contains(p) { tool = t; return true }
        for (hex, box) in layout.colorBoxes where box.insetBy(dx: -3, dy: -3).contains(p) { colorHex = hex; return true }
        return true
    }

    // MARK: - mouse

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if OverlayChrome.cancelHitRect(in: bounds).contains(p) {
            MSLog.info(.overlay, "cancel button pressed")
            if let host { delegate?.overlayDidCancel(host) }
            return
        }
        guard !hitToolbar(p) else { needsDisplay = true; return }
        if let editing = textEditing {
            // 点到编辑框外＝先把这段文字了结（提交），再走正常路由；框内交给 field editor 自己
            if !editing.textView.frame.contains(p) { commitTextEditing() }
            else { return }
        }
        if tool == .text, let sel = selection, sel.contains(p) {
            beginTextEditing(at: docPoint(p, in: sel))
            return
        }
        if tool.isClickAction, let sel = selection, sel.contains(p) {
            performClickAction(at: docPoint(p, in: sel))
            return
        }
        if tool == .select, let sel = selection, sel.contains(p) {
            let dp = MSIntPoint.canvasPoint(of: p, in: sel, scale: display.scale)
            if let hit = elementAt(dp) {
                selectedID = hit.id
                if let before = document?.elements.first(where: { $0.id == hit.id }) {
                    dragMode = .moveElement(recorder: MSDragRecorder(element: before), grab: dp)
                }
                needsDisplay = true
                return
            }
            selectedID = nil          // 点空白＝取消选择
            needsDisplay = true
        }
        if let tool = tool.annotationKind, let sel = selection, sel.contains(p) {
            dragMode = .draw(start: p)
            draft = MSAnnotationElement(kind: tool, points: [docPoint(p, in: sel), docPoint(p, in: sel)],
                                        style: currentStyle(), variant: tool == .freehand && self.tool.isFreehandPen ? "pen" : nil)
            host.map { delegate?.overlay($0, drawingPhaseDidChange: .began(tool)) }   // tool 这里已是 MSAnnotationKind
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

    /// `N` 序号＝放一个自增徽章；`E` 橡皮擦＝删掉点到的最上层元素。
    /// 两者都是"一次动作 = 一条撤销记录"（`ADR-011`）；徽章的计数自增和插入打包成一条，
    /// 所以撤销徽章会把号码也退回去，不会留下空号。
    /// 命中的最上层元素（z 最大）。命中区由 `MSAnnotationGeometry.hitTest` 定：
    /// 未填充形状只有轮廓可命中，填充形状内部也算。
    func elementAt(_ dp: MSIntPoint) -> MSAnnotationElement? {
        guard let doc = document else { return nil }
        let p = CGPoint(x: dp.x, y: dp.y)
        return doc.elements
            .filter { MSAnnotationGeometry.hitTest(p, element: $0, extraTolerance: 4) }
            .max { $0.z < $1.z }
    }

    func performClickAction(at dp: MSIntPoint) {
        guard var doc = document else { return }
        switch tool {
        case .badge:
            let before = doc.badgeCounter
            let element = MSAnnotationElement(kind: .badge, points: [dp], style: currentStyle(), text: String(before))
            history.apply(.composite([.insert(element), .badgeCounter(before: before, after: before + 1)]), to: &doc)
            MSLog.info(.annotate, "badge #\(before) at \(dp.x),\(dp.y)")
        case .eraser:
            let p = CGPoint(x: dp.x, y: dp.y)
            guard let victim = doc.elements.filter({ MSAnnotationGeometry.hitTest(p, element: $0, extraTolerance: 4) })
                        .max(by: { $0.z < $1.z }) else {
                MSLog.debug(.annotate, "eraser 没命中任何元素 \(dp.x),\(dp.y)")
                return
            }
            history.apply(.remove(victim), to: &doc)
            MSLog.info(.annotate, "eraser 删除 kind=\(victim.kind.rawValue) z=\(victim.z)")
        default:
            return
        }
        document = doc
        cachedComposite = nil
        needsDisplay = true
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
        case .moveElement(var recorder, let grab):
            guard let sel = selection, let id = selectedID else { return }
            let dp = MSIntPoint.canvasPoint(of: p, in: sel, scale: display.scale)
            let dx = dp.x - grab.x, dy = dp.y - grab.y
            guard var doc = document, let idx = doc.elements.firstIndex(where: { $0.id == id }) else { return }
            var moved = doc.elements[idx]
            moved.points = moved.points.map { MSIntPoint(x: $0.x + dx, y: $0.y + dy) }
            recorder.update(moved)
            doc.elements[idx] = moved
            document = doc
            cachedComposite = nil
            dragMode = .moveElement(recorder: recorder, grab: grab)
            needsDisplay = true
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
        if case .moveElement(let recorder, _) = dragMode {
            // 上百次 mouseDragged 只留一条记录；没真移动过就不留（`FR-ANN-005` 判据）
            if let command = recorder.command, var doc = document {
                history.apply(command, to: &doc)
                document = doc
                cachedComposite = nil
                MSLog.info(.history, "元素拖动收尾：一条记录")
            }
            needsDisplay = true
            return
        }
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

    /// 把"文档里现在有几个元素"报给会话（`ST-001` 行 9/10 的生产者）。
    /// 任何改动元素层的路径都必须调它，否则 `hasElements` 会说谎——而行 7 的清空提示正依赖这个事实。
    func reportElementCount() {
        guard let host else { return }
        delegate?.overlay(host, elementCount: document?.elements.count ?? 0)
    }

    /// 右键＝退出截图。给"键盘完全失灵"的人留一条鼠标出路。
    public override func rightMouseDown(with event: NSEvent) {
        MSLog.info(.overlay, "right click → cancel")
        cancel()
    }

    private func cancel() { if let host { delegate?.overlayDidCancel(host) } }
    public func cancelViaEscape() { MSLog.info(.overlay, "cancel via Esc path"); cancel() }

    // MARK: - 文字输入子态（ST-003）

    /// field editor 的状态。`elementID == nil` 是新建，否则是在改既有元素的文本。
    private struct TextEditing {
        let elementID: UUID?
        let anchor: MSIntPoint
        let before: MSAnnotationElement?
        let textView: NSTextView
    }

    private var textEditing: TextEditing?

    /// 现在是不是在"文字输入"子态里（状态机查询点，测试也用它）。
    public var isEditingText: Bool { textEditing != nil }

    /// 测试缝：当前 field editor（不在编辑态时为 nil）。写它的 `string` 等价于用户敲完这段字。
    var editorTextView: NSTextView? { textEditing?.textView }

    /// 画布锚点 → field editor 的视图矩形。锚点是**文字左上角**，而视图 y 向上，所以框向下长。
    /// 字号从画布像素换算回点（`/scale`），与渲染器在导出/显示两路上用的是同一个字号语义。
    static func editorFrame(anchor: MSIntPoint, selection: CGRect, scale: CGFloat,
                            fontSize: Int, lines: Int = 1, width: CGFloat = 260) -> CGRect {
        let top = anchor.viewPoint(in: selection, scale: scale)
        let lineHeight = max(10, CGFloat(fontSize) / scale * 1.32)
        let height = lineHeight * CGFloat(max(1, lines)) + 4
        return CGRect(x: top.x, y: top.y - height, width: width, height: height)
    }

    func beginTextEditing(at dp: MSIntPoint, existing: MSAnnotationElement? = nil) {
        guard selection != nil else { return }
        if textEditing != nil { finishTextEditing() }
        let style = currentStyle()
        let tv = NSTextView()
        tv.string = existing?.text ?? ""
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: max(9, CGFloat(style.fontSize) / display.scale))
        tv.textColor = NSColor(cgColor: style.stroke.cgColor) ?? .white
        tv.insertionPointColor = NSColor(cgColor: style.stroke.cgColor) ?? .white
        tv.textContainerInset = NSSize(width: 2, height: 2)
        tv.frame = Self.editorFrame(anchor: dp, selection: selection ?? bounds,
                                    scale: display.scale, fontSize: style.fontSize)
        addSubview(tv)
        window?.makeFirstResponder(tv)
        textEditing = TextEditing(elementID: existing?.id, anchor: dp, before: existing, textView: tv)
        needsDisplay = true
        MSLog.info(.annotate, "text editing begin at \(dp.x),\(dp.y) font=\(style.fontSize)px existing=\(existing != nil)")
    }

    /// `⌘Enter` / `Enter` 提交。空文本**不入撤销记录**（否则用户要为一件没发生的事按 `⌘Z`）。
    @discardableResult
    func commitTextEditing() -> Bool {
        guard let editing = textEditing else { return false }
        let text = editing.textView.string
        finishTextEditing()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            MSLog.info(.annotate, "text commit skipped（空文本）")
            return false
        }
        guard var doc = document else { return false }
        if let before = editing.before {
            var after = before
            after.text = text
            history.apply(.replace(before: before, after: after), to: &doc)
        } else {
            history.apply(.insert(MSAnnotationElement(kind: .text, points: [editing.anchor],
                                                     style: currentStyle(), text: text)), to: &doc)
        }
        document = doc
        cachedComposite = nil
        needsDisplay = true
        MSLog.info(.annotate, "text committed chars=\(text.count) lines=\(text.components(separatedBy: "\n").count)")
        return true
    }

    /// `Esc` 放弃输入：只退子态，**不退整个遮罩**（ST-003 的注意栏，也是 `FR-SESS-002` 不被削弱的前提）。
    func abortTextEditing() {
        guard textEditing != nil else { return }
        finishTextEditing()
        MSLog.info(.annotate, "text editing aborted（无记录）")
    }

    private func finishTextEditing() {
        textEditing?.textView.removeFromSuperview()
        textEditing = nil
        needsDisplay = true
    }

    /// 子态内的按键：`Esc` 放弃 / `Enter`·`⌘Enter` 提交 / `⇧Enter` 换行；
    /// 其余（含 `⌘C/⌘V/⌘Z` 和删除键）返回 false 交回 field editor，**不许**落到会话分支上去抢。
    private func handleTextKey(_ event: NSEvent) -> Bool {
        guard textEditing != nil else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:
            abortTextEditing(); return true
        case 36, 76:
            if flags.contains(.shift) { return false }   // 换行交给 field editor：它本来就吃 ⇧Enter
            commitTextEditing(); return true
        default:
            return false
        }
    }

    /// View point (y-up) → canvas pixel of the current selection (y-down)。
    /// 换算本体在 `MSCore`，和逆运算 `viewPoint(in:scale:)` 放在一起成对测（ADR-013）。
    /// internal：`@testable` 用它把视图点换成画布点，测试因此不必自己再算一遍坐标（算错就是第二个 ✕）。
    func docPoint(_ p: NSPoint, in sel: CGRect) -> MSIntPoint {
        MSIntPoint.canvasPoint(of: p, in: sel, scale: display.scale)
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
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// 返回是否已消费。遮罩同时挂了本地事件监视器（`MSOverlayWindow`），
    /// 因为键到底走 responder 还是 monitor 取决于 app 激活时序，两条都要通。
    @discardableResult
    public func handleKey(_ event: NSEvent) -> Bool {
        if textEditing != nil { return handleTextKey(event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:
            guard let host else { return false }
            delegate?.overlayDidCancel(host)
            return true                                                       // Esc
        case 36, 76:                                                       // Enter
            commit(defaultIntent(from: host.flatMap { delegate?.overlayPreferences($0) })); return true
        case 8 where flags.contains(.command):                             // ⌘C
            guard let host else { return false }
            delegate?.overlay(host, didRequest: .copy); return true
        case 35 where flags.contains(.command):                            // ⌘P
            guard let host else { return false }
            delegate?.overlay(host, didRequest: .pin); return true
        case 1 where flags.contains(.command):                             // ⌘S / ⌘⇧S
            guard let host else { return false }
            delegate?.overlay(host, didRequest: flags.contains(.shift) ? .quickSave : .savePanel); return true
        case 49 where flags.contains(.option):                             // ⌥Space 预留
            return false
        case 6 where flags.contains(.command):                             // ⌘Z / ⇧⌘Z
            if flags.contains(.shift) { redo() } else { undo() }; return true
        case 30 where flags.contains(.command):                            // ⌘] 上移一层
            changeLayer(up: true); return true
        case 38 where flags.contains(.command):                            // ⌘[ 下移一层
            changeLayer(up: false); return true
        case 51, 117:                                                       // Delete / Backspace
            if selection == nil { return false }
            deleteSelectedOrLast(); return true
        default:
            guard selection != nil || MSTool.allCases.contains(where: { $0.letter.lowercased() == event.charactersIgnoringModifiers?.lowercased() }) else { return false }
            if let t = MSTool.allCases.first(where: { $0.letter.lowercased() == event.charactersIgnoringModifiers?.lowercased() }),
               !flags.contains(.command) {
                // ST-003 工具待落笔：再按同一个键＝收回工具，回到选择态
                tool = (t == self.tool && t != .select) ? .select : t
                needsDisplay = true
                return true
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "]": lineWidth = min(12, lineWidth + 1); needsDisplay = true; return true
            case "[": lineWidth = max(1, lineWidth - 1); needsDisplay = true; return true
            default: return false
            }
        }
        return false
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

    /// `FR-ANN-004`：Delete 删**选中**的元素；没选中才退回"删最上层"（旧行为，别让人按了没反应）。
    func deleteSelectedOrLast() {
        guard var doc = document else { return }
        let target = selectedID.flatMap { id in doc.elements.first { $0.id == id } }
            ?? doc.elements.max(by: { $0.z < $1.z })
        guard let victim = target else { return }
        history.apply(.remove(victim), to: &doc)
        if selectedID == victim.id { selectedID = nil }
        document = doc; cachedComposite = nil; needsDisplay = true
    }

    /// z 序上移/下移（`⌘]` / `⌘[`）。没选中就什么都不做——层级是元素属性，不是全局动作。
    func changeLayer(up: Bool) {
        guard var doc = document, let id = selectedID, doc.elements.contains(where: { $0.id == id }) else {
            MSLog.debug(.annotate, up ? "raise 无选中，忽略" : "lower 无选中，忽略")
            return
        }
        if up { doc.raise(id: id) } else { doc.lower(id: id) }
        document = doc
        cachedComposite = nil
        needsDisplay = true
        let z = doc.elements.first { $0.id == id }?.z ?? -1
        MSLog.info(.annotate, "layer \(up ? "up" : "down") z=\(z)")
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
