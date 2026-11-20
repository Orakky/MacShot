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
    /// 选区变化后**落到范围外**被清掉的条数（0 不通知）。文案必须说清"只清了外面那些"，
    /// 不许再写"原有标注已清空（无法撤销）"——11-18 改判后范围内的原地保留、且可撤销。
    func overlay(_ overlay: MSOverlayWindow, didDropAnnotations count: Int)
    func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent)
    func overlayDidCancel(_ overlay: MSOverlayWindow)
    /// 标注绘制的起止（`ST-001` 行 9/10）。会话靠它把 `selecting ⇄ editing` 走起来，
    /// 并在 `drawEnded` 后知道文档里已经有元素——行 7 的"改选区清空要提示"依赖这个事实。
    /// 此前 `drawBegan/drawEnded` 两个事件**没有任何生产者**，所以 `hasElements` 永远是 false。
    func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase)
    /// 元素层数量变了（提交/删除/撤销/清空）。`didSet` 自动报，不靠调用点记得。
    func overlay(_ overlay: MSOverlayWindow, elementCount: Int)
    /// 放大镜里按了 `C`：把取样色串交给会话写剪贴板（`FR-CAP-016`）。
    /// 视图不自己碰 `NSPasteboard`——剪贴板是会话与导出层的事，测试才有单一入口。
    func overlay(_ overlay: MSOverlayWindow, didPickColor text: String)
    /// Asks the session for the cropped pixels under a view-space rect (frozen frame, no re-capture).
    func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage?
    func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences
}

public extension MSOverlayDelegate {
    /// 不关心"清了几条"的表面（贴图侧、测试替身）不必被迫实现。
    func overlay(_ overlay: MSOverlayWindow, didDropAnnotations count: Int) {}
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
        // 这里原来还拆一个**全局** keyDown 监视器（`escapeWatch`）。11-19 权限收缩时整条摘掉：
        // 它需要输入监控级权限、监听全系统按键，而没给权限时它根本不响——一条"看起来是保险、
        // 实际靠权限运气"的路径不该算逃生阀。真出路有五条：本地 keyMonitor 的 Esc、responder
        // 链的 Esc、✕ 按钮、右键取消、再按一次热键（`V-063②` 数着）。
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
    /// 这三个字段的**真源是设置**（`annotationDefaults` → `MSAnnotationStyleSpec`），
    /// 这里的值只是"还没接到偏好"时的兜底。以前它们被写死在这里，`annotationStyle()` 没有
    /// 任何调用者 ⇒ 用户在设置里改描边色/线宽/字号/模糊半径全都不生效（A-11 的真身，`E-069`）。
    public var colorHex: String = "#E83347"
    public var lineWidth: Int = 3
    public var blurRadius: Int = 14
    public var fontSize: Int = 18
    /// 拖新选区时是否自动呼出放大镜——真源是设置里的 `showMagnifierWhileDragging`。
    /// 以前这个开关没有任何消费者（`B-037`），所以"关掉放大镜"改什么都不发生。
    public var autoLoupeWhileDragging = true

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

    /// 拖选区（移动/改尺寸）的**基准**：起点矩形 + 起点元素表。
    /// 逐帧从基准算总位移，而不是在上一帧已取整的点上继续加——鼠标给的位移是小数（3.5 / 2.5 pt），
    /// 每帧各自取整会累积漂移：11-20 在 scale 1 下实测四帧少走 2px，观感就是"箭头慢慢跟着视窗爬"。
    private var selectionDragBaseline: (rect: CGRect, elements: [MSAnnotationElement])?
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
        let previous = selection
        selection = rect
        // 顺序有讲究：先让会话知道"选区变了"（此时 `hasElements` 还是改动前的真值，
        // 行 7 才能提示），再真的换掉文档。反过来就永远不提示。
        if let size = rect?.size, let previousSize, size != previousSize, document?.isEmpty == false {
            host.map { delegate?.overlay($0, selectionDidChange: rect) }
        }
        if let rect, let previous, previous != rect, document?.isEmpty == false {
            // Q-11 的旧档是"改选区＝全清、且不可撤销"。用户 11-18 改判：
            // **屏幕位置落在新选区里的标注原地保留**，只有跑到外面的才清掉，而且这是一条可撤销记录。
            retargetElements(from: previous, to: rect)
        } else if let rect {
            document = ensureDocument(for: rect)
        }
        cachedComposite = nil
        needsDisplay = true
        delegate?.overlay(host ?? MSOverlayWindow(display: display, frame: frozenFrame), selectionDidChange: rect)
    }

    /// 选区变了 ⇒ 元素平移到新画布（平移量只问 `MSIntPoint.documentDelta` 要），
    /// 落到新选区外面的清掉；整件事合成**一条**撤销记录，`⌘Z` 一次回到改动前。
    private func retargetElements(from old: CGRect, to new: CGRect) {
        guard let before = document else { return }
        // 有拖拽基准就用基准：位移按"起点→当前"一次算清，元素坐标也从起点那份表出发，
        // 这样每帧的取整只发生一次，不会逐帧叠加成漂移（判据 `V-070`）。
        let baseRect = selectionDragBaseline?.rect ?? old
        let baseElements = selectionDragBaseline?.elements ?? before.elements
        let canvas = canvasSize(for: new)
        let d = MSIntPoint.documentDelta(selectionOld: baseRect, to: new, scale: display.scale)
        let area = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        var steps: [MSAnnotationCommand] = []
        var dropped = 0
        for element in baseElements {
            let moved = element.translated(by: d)
            let inside = MSAnnotationGeometry.bounds(of: moved).map { $0.cgRect.intersects(area) } ?? true
            if !inside { steps.append(.remove(element)); dropped += 1; continue }
            if moved.points != element.points || moved.boundsOverride != element.boundsOverride {
                steps.append(.replace(before: element, after: moved))
            }
        }
        var next = MSAnnotationDocument(canvasSize: canvas, elements: baseElements,
                                        currentStyle: before.currentStyle, badgeCounter: before.badgeCounter)
        if let command = MSAnnotationCommand.compose(steps) { history.apply(command, to: &next) }
        document = next
        if dropped > 0 { host.map { delegate?.overlay($0, didDropAnnotations: dropped) } }
        MSLog.info(.overlay, "selection changed \(old.integral) → \(new.integral): kept \(next.elements.count), dropped \(dropped)")
    }

    private func canvasSize(for rect: CGRect) -> MSIntSize {
        // 画布尺寸**必须就是这一帧取样用的那个设备矩形**，不许自己再按"尺寸 × scale"round 一遍：
        // `croppedSource` 走 `pixelRect`（两条边各取整再相减），两条路各算一次就会差 1px，
        // 于是 `render` 把 301px 的底图塞进 300px 的画布、再按选区放大画回屏幕
        // ⇒ 背景逐帧非整数重采样、标注却按整数画 = 用户 11-20 答的"位置不动、边缘在闪"（`V-070`）。
        // 先吸附再换算，使画布 / 取样 / `documentDelta` 三条量落在同一张设备网格上；
        // 设备顶 = `pixelRect.minY` 与元素平移同源 ⇒ 标注的设备行由构造恒定，不再靠"尺寸别抖"撑着。
        let snapped = MSIntPoint.snappedToPixelGrid(rect, scale: display.scale)
        if let pixel = display.pixelRect(forLogical: globalRect(snapped)) { return pixel.size }
        // 选区还在拖成 0×0（或整块跑到屏外）时 `pixelRect` 返回 nil，这里退回浮点尺寸。
        let w = Int((rect.width * display.scale).rounded()), h = Int((rect.height * display.scale).rounded())
        return w > 0 && h > 0 ? MSIntSize(width: w, height: h) : .zero
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
        let scrim = OverlayChrome.scrimAlpha(isDark: chromeIsDark)   // 明暗由设置的 appearance 决定（经窗口 appearance 落地）

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
            selfCheckChromeSweep()      // 同帧真值：chrome 落位必须在它算完之后比
        } else {
            ctx.setFillColor(MSColorRGBA.rgba(0, 0, 0, scrim).cgColor)
            ctx.fill(bounds)
            drawHint(in: ctx)
        }
        drawLoupe(in: ctx)
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
    private func drawSelectionContents(_ rawSel: CGRect, in ctx: CGContext) {
        guard rawSel.width > 1, rawSel.height > 1 else { return }
        // 绘制目标吸附到设备像素网格：小数原点 + 像素精确的烘焙图 = 逐帧 ±1px 微抖（见 `MSIntPoint.snappedToPixelGrid`）。
        let sel = MSIntPoint.snappedToPixelGrid(rawSel, scale: display.scale)
        let cropped = croppedSource(for: sel)
        let composite = compositedCrop(for: sel)

        ctx.saveGState()
        ctx.interpolationQuality = .none
        if let composite { ctx.draw(composite, in: sel) }
        else if let cropped { ctx.draw(cropped, in: sel) }
        ctx.restoreGState()
        // 拖拽中的草稿走矢量层，和提交后的元素同一条渲染路径：所见=所存。
        if draft != nil, let source = cropped { drawDraft(in: sel, source: source, in: ctx) }
        v070AnnoViewRect = document?.elements.first.flatMap { element in
            MSAnnotationGeometry.bounds(of: element).map { box in
                CGRect(x: sel.minX + CGFloat(box.minX) / display.scale,
                       y: sel.maxY - CGFloat(box.maxY) / display.scale,
                       width: CGFloat(box.width) / display.scale, height: CGFloat(box.height) / display.scale)
            }
        }
        selfCheckDragGeometry(drawSel: sel, rawSel: rawSel, drawn: composite ?? cropped)
    }

    // MARK: - `V-070` 拖动自检（只在真机上才有的那一半证据）

    /// 一次"移动视窗"拖动结束时打**一条**读数：帧数、其中小数边几帧、`crop ≠ 画布`几帧、标注设备行变了多少次。
    /// 为什么要留：上一轮的临时日志打的是**吸附后**的矩形，在 scale 1 下永远显示 `.00`，
    /// 于是"真机的输入到底是不是小数"这个前提它答不了（`E-110`）。这条把原始 `maxY × scale` 的分数部分一起带出来。
    private var v070Frames = 0
    private var v070Fractional = 0
    private var v070Unpaired = 0
    private var v070RowChanges = 0
    private var v070LastRow: Int?
    private var v070Anchor: UUID?
    /// 药丸本轮画在哪（`drawReadout` 写）与标注在视图里的外接框（`drawSelectionContents` 写）。
    /// 拖动时工具条/药丸会**扫过**标注：这两个量一比就知道"闪"是不是盖造成的（`E-110` 的另一支）。
    private var readoutRect: CGRect?
    private var v070AnnoViewRect: CGRect?
    private var v070CoverChanges = 0
    private var v070WasCovered: Bool?

    private func selfCheckDragGeometry(drawSel: CGRect, rawSel: CGRect, drawn: CGImage?) {
        guard case .move = dragMode, let drawn, let canvas = document?.canvasSize,
              let anchor = document?.elements.first,
              let pixel = display.pixelRect(forLogical: globalRect(drawSel)) else { return }
        // 锚点换了元素（被裁掉/被清掉）就不是同一条量，累计值作废，免得把"换了元素"报成"抖"。
        if let v070Anchor, v070Anchor != anchor.id {
            v070Frames = 0; v070Fractional = 0; v070Unpaired = 0; v070RowChanges = 0
        }
        v070Anchor = anchor.id
        v070Frames += 1
        if (rawSel.maxY * display.scale).truncatingRemainder(dividingBy: 1) != 0 { v070Fractional += 1 }
        if drawn.width != canvas.width || drawn.height != canvas.height { v070Unpaired += 1 }
        let row = pixel.minY + (anchor.points.first?.y ?? 0)
        if let last = v070LastRow, last != row { v070RowChanges += 1 }
        v070LastRow = row
    }

    /// 工具条/药丸是否压在这一条标注上，以及**这个"压/没压"逐帧变了没有**——
    /// 变一次就是一次"箭头被 chrome 扫过去"，观感＝位置不动、边上闪一下。
    private func selfCheckChromeSweep() {
        guard case .move = dragMode, let anno = v070AnnoViewRect else { return }
        let covered = [toolbarLayout?.rect, readoutRect].compactMap { $0 }.contains { $0.intersects(anno) }
        if let was = v070WasCovered, was != covered { v070CoverChanges += 1 }
        v070WasCovered = covered
    }

    private func logDragGeometryCheck() {
        guard case .move = dragMode, v070Frames > 0 else { return }
        MSLog.info(.overlay, "V-070 拖动自检：帧=\(self.v070Frames) 小数边=\(self.v070Fractional) "
                            + "取样≠画布=\(self.v070Unpaired) 设备行变化=\(self.v070RowChanges) "
                            + "chrome 扫过标注=\(self.v070CoverChanges)")
        v070Frames = 0; v070Fractional = 0; v070Unpaired = 0; v070RowChanges = 0; v070LastRow = nil; v070CoverChanges = 0; v070WasCovered = nil; v070Anchor = nil
    }

    /// 边画边看到形状跟着走（`FR-ANN-002`）。贴图编辑器一直有这一层（`MSPinWindow` 的 draft），
    /// 遮罩这边只更新状态不上屏，于是"松手才出现"，体感就是标注卡死。
    /// 模糊是唯一例外：每帧对整块区域跑 CPU 盒式模糊会真掉帧，拖拽期只画轮廓、松手才糊。
    private func drawDraft(in sel: CGRect, source: CGImage, in ctx: CGContext) {
        guard let draft else { return }
        let canvas = MSIntSize(width: source.width, height: source.height)
        ctx.saveGState()
        ctx.clip(to: sel)
        ctx.translateBy(x: sel.minX, y: sel.minY)
        ctx.scaleBy(x: sel.width / CGFloat(canvas.width), y: sel.height / CGFloat(canvas.height))
        if draft.kind == .blur {
            // 这一支自己落笔，所以要自己进文档坐标（y-down）；矢量层交给 renderElements 翻正。
            ctx.translateBy(x: 0, y: CGFloat(canvas.height))
            ctx.scaleBy(x: 1, y: -1)
            guard let box = MSAnnotationGeometry.bounds(of: draft) else { ctx.restoreGState(); return }
            ctx.setStrokeColor(MSColorRGBA.rgb(255, 255, 255).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(CGRect(x: CGFloat(box.minX), y: CGFloat(box.minY),
                              width: CGFloat(box.width), height: CGFloat(box.height)))
        } else {
            var doc = document ?? MSAnnotationDocument(canvasSize: canvas)
            doc.elements = [draft]
            renderer.renderElements(of: doc, into: ctx, source: source, canvas: canvas, intent: .preview)
        }
        ctx.restoreGState()
    }

    private func compositedCrop(for sel: CGRect) -> CGImage? {
        guard let document, !document.elements.isEmpty, let source = croppedSource(for: sel) else { return nil }
        if let cachedComposite, cachedElements == document.elements, cachedSourceSize == source.width * 1_000_000 + source.height {
            return cachedComposite
        }
        compositeBakeCount += 1            // V-053④ 的读数：拖拽期应当一次都不增
        let image = renderer.render(document, source: source, intent: .preview)
        cachedComposite = image
        cachedElements = document.elements
        cachedSourceSize = source.width * 1_000_000 + source.height
        return image
    }

    /// 整文档重烘焙的次数。**判据用得上**：拖拽草稿只该多画一个矢量元素，不该逐帧重烤整叠元素
    /// （那才是"标注越画越卡"的形状）。V-053④ 读它，而不是读耗时（尾表：耗时 Δ 不当选点前提）。
    public private(set) var compositeBakeCount = 0
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

    // MARK: - 放大镜（`UI-008` / `FR-CAP-016`）

    /// 指针位置（视图坐标）。`nil` ⇒ 还没动过鼠标，不画。
    private var loupeAnchor: CGPoint?
    /// `⌥` 强制显示；拖新选区时自动显示（规格："自动出现（拖拽时）、⌥ 强制"）。
    public private(set) var loupeForced = false
    public private(set) var loupeFormat: MSLoupeModel.Format = .hex
    /// 拖拽中标记：由 `mouseDown/mouseUp` 维护，放大镜据此自动出现。
    private var isDraggingSelection = false
    /// 一次解码服务多次取样：放大镜每次 `mouseMoved` 都要取样，不能每帧重解整屏。
    private lazy var loupeBitmap: MSBitmap? = MSBitmap(image: frozenFrame)

    /// 当前指针下的像素坐标（换算显式写在 `MSLoupeModel.pixel`，`ADR-013`）。
    public var loupePixel: MSIntPoint? {
        guard let p = loupeAnchor else { return nil }
        return MSLoupeModel.pixel(view: p, viewHeight: bounds.height,
                                  imageSize: MSIntSize(width: frozenFrame.width, height: frozenFrame.height),
                                  scale: display.scale)
    }

    public var loupeColor: MSColorRGBA? {
        guard let px = loupePixel else { return nil }
        return loupeBitmap?.sample(pixelAt: px)
    }

    /// 探针读数用：拖拽中的草稿是什么种类（不把可变引用递出去）。
    public var draftKindForProbe: MSAnnotationKind? { draft?.kind }

    /// 探针/测试用：这次拖拽到底走了哪条支路（移动视窗 / 拖角改尺寸 / 拖元素）。
    /// 上一轮判据不成立就有这个因素——抓取点离角 12pt 可能命中的是把手。
    public var dragModeForProbe: String {
        switch dragMode {
        case .newSize: return "newSize"
        case .move: return "move"
        case .resize: return "resize"
        case .moveElement: return "moveElement"
        case .draw: return "draw"
        case nil: return "nil"
        }
    }

    /// 探针读数用：已提交元素数（拖拽中该是 0，屏幕上的墨来自草稿）。
    public var committedElementCount: Int { document?.elements.count ?? -1 }

    /// 放大镜该不该出现。
    public var isLoupeVisible: Bool {
        loupeAnchor != nil && ((isDraggingSelection && autoLoupeWhileDragging) || loupeForced)
    }

    /// 遮罩 chrome 走深色还是浅色。窗口 `appearance` 由会话按设置覆盖后，
    /// `effectiveAppearance` 就会跟着变，这里只读不算——两套判断会打架。
    public var chromeIsDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `C` 复制的串（空串 ⇒ 没什么可复制）。
    public func loupeCopyString() -> String {
        MSLoupeModel.copyString(color: loupeColor, format: loupeFormat)
    }

    public func cycleLoupeFormat() { loupeFormat = loupeFormat.next }

    /// 画放大镜。格子颜色**必须**等于取样色——这条是 `FR-CAP-016` 判据里"放大镜内像素与屏幕
    /// 逐点一致"的落点，测试直接量中心格的颜色，不看状态变量。
    func drawLoupe(in ctx: CGContext) {
        guard isLoupeVisible, let anchor = loupeAnchor else { return }
        let handles = selection.map { sel in handlePoints(of: sel).map { CGRect(x: $0.x - 5.5, y: $0.y - 5.5, width: 11, height: 11) } } ?? []
        let box = MSLoupeModel.rect(anchor: anchor, bounds: bounds, handleRects: handles)
        let grid = MSLoupeModel.gridRect(in: box)   // 单一来源：与 centerCell 同一块地

        ctx.saveGState()
        // 外框：float.surface + 描边（design-system §6 的浮层配方）
        ctx.setFillColor(MSColorRGBA.rgba(28, 28, 30, 0.98).cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(MSColorRGBA.rgb(120, 120, 124).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // 近邻放大：不许插值，否则"像素"就不是像素了。
        if let px = loupePixel,
           let mag = MSImageSampler.magnified(frozenFrame, center: px, radius: MSLoupeModel.radius,
                                              zoom: MSLoupeModel.zoom) {
            ctx.interpolationQuality = .none
            ctx.draw(mag, in: grid)
        }
        // 网格线（17×17）
        ctx.setStrokeColor(MSColorRGBA.rgba(255, 255, 255, 0.10).cgColor)
        ctx.setLineWidth(1)
        let cell = grid.width / CGFloat(MSLoupeModel.pixelCount)
        for i in 0...MSLoupeModel.pixelCount {
            let x = grid.minX + CGFloat(i) * cell
            ctx.move(to: CGPoint(x: x, y: grid.minY)); ctx.addLine(to: CGPoint(x: x, y: grid.maxY))
            let y = grid.minY + CGFloat(i) * cell
            ctx.move(to: CGPoint(x: grid.minX, y: y)); ctx.addLine(to: CGPoint(x: grid.maxX, y: y))
            ctx.strokePath()
        }
        // 中心像素描 accent
        let center = MSLoupeModel.centerCell(in: box)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(center)

        // 读数条：色块 + 串（font.readout）
        let readout = CGRect(x: box.minX + 1, y: box.minY + 1, width: box.width - 2,
                             height: MSLoupeModel.readoutHeight - 2)
        if let c = loupeColor {
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: readout.minX + 6, y: readout.midY - 6, width: 12, height: 12))
        }
        let text = MSLoupeModel.readout(color: loupeColor, pixel: loupePixel ?? .zero, format: loupeFormat)
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]).draw(at: NSPoint(x: readout.minX + 24, y: readout.midY - 7))
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
        readoutRect = CGRect(origin: p, size: size)
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
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor)
                ctx.fill(box)
            }
            // 图标优先，画不出来才回落字母——绝不许出现"格子在、里面空"（design-system §5）。
            if !MSOverlayIcons.draw(t, in: box, tint: t == tool ? .controlAccentColor : .labelColor) {
                NSAttributedString(string: t.letter, attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
                ]).draw(at: NSPoint(x: box.midX - 4, y: box.midY - 8))
            }
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
            // 逐段画在 actionBoxes 给的格子里：绘制与命中读同一份几何，
            // 以前是"一整串画在 rect.maxX - 240"（魔数），根本没有命中区。
            for (action, box) in actionBoxes(in: rect) {   // 与 visibleActionBoxes 同一份几何
                NSAttributedString(string: actionLabels()[action] ?? action.label(verb: "贴出"), attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                ]).draw(at: NSPoint(x: box.minX, y: box.midY - 7))
            }
        }
        ctx.restoreGState()
    }

    /// 工具条命中结果。动作格必须**单独成档**：整条一律 `true` 的话，点"贴出"和点空白一样
    /// 什么都没发生（用户 11-18 报的第 1 条）。
    enum ToolbarHit {
        case tool(MSTool), color(String), action(MSAnnotationToolbar.BarAction), blank
    }

    /// 命中区直接取绘制用的同一份 layout：两处各算一遍就是 ✕ 那个 bug 的成因。
    private func toolbarHit(_ p: NSPoint) -> ToolbarHit? {
        guard let layout = toolbarLayout, layout.rect.contains(p) else { return nil }
        for (t, box) in layout.toolBoxes where box.contains(p) { return .tool(t) }
        for (hex, box) in layout.colorBoxes where box.insetBy(dx: -3, dy: -3).contains(p) { return .color(hex) }
        for (a, box) in visibleActionBoxes() where box.contains(p) { return .action(a) }
        return .blank
    }

    /// 动作格子的标签：`.commit` 那一格跟随设置项 `commitBehavior` 的动词，
    /// 否则"点一个写着贴出的按钮却复制了"这种自相矛盾就会出现在屏幕上。
    private func actionLabels() -> [MSAnnotationToolbar.BarAction: String] {
        let verb = host.flatMap { delegate?.overlayPreferences($0) }?.commitBehavior.shortLabel ?? "贴出"
        return Dictionary(uniqueKeysWithValues: MSAnnotationToolbar.BarAction.allCases.map { ($0, $0.label(verb: verb)) })
    }

    private func actionBoxes(in rect: CGRect) -> [(action: MSAnnotationToolbar.BarAction, rect: CGRect)] {
        MSAnnotationToolbar.actionBoxes(rect: rect, labels: actionLabels())
    }

    /// 窄屏时动作文字整段不画（`showsActions` 先收提示文字、不收工具），
    /// 所以命中区也必须一起收——否则格子压在色板上，点色块会误触发"保存"。
    private func visibleActionBoxes() -> [(action: MSAnnotationToolbar.BarAction, rect: CGRect)] {
        guard let layout = toolbarLayout, layout.showsActions else { return [] }
        return actionBoxes(in: layout.rect)
    }

    /// 探针与测试用的只读视图：**画出来的**动作格（没画就不该能点）。
    public var actionBoxesForProbe: [(action: MSAnnotationToolbar.BarAction, rect: CGRect)] { visibleActionBoxes() }

    // MARK: - mouse

    public override func mouseMoved(with event: NSEvent) {
        loupeAnchor = convert(event.locationInWindow, from: nil)
        loupeForced = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
        if isLoupeVisible || loupeForced { needsDisplay = true }
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if OverlayChrome.cancelHitRect(in: bounds).contains(p) {
            MSLog.info(.overlay, "cancel button pressed")
            if let host { delegate?.overlayDidCancel(host) }
            return
        }
        switch toolbarHit(p) {
        case .tool(let t): tool = t; needsDisplay = true; return
        case .color(let hex): colorHex = hex; needsDisplay = true; return
        case .action(let a):
            MSLog.info(.overlay, "toolbar action=\(a.rawValue)")
            needsDisplay = true
            switch a {
            case .commit: commit(defaultIntent(from: host.flatMap { delegate?.overlayPreferences($0) }))
            case .copy: commit(.copy)
            case .save: commit(.savePanel)
            case .cancel: if let host { delegate?.overlayDidCancel(host) }
            }
            return
        case .blank: needsDisplay = true; return
        case nil: break
        }
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
        // 走到这里才是"拖选区"（新框 / 移动 / 改尺寸）——放大镜的拖拽档只认这一种。
        // 以前 mouseDown 一进来就置位，画箭头/矩形也算"拖拽"，标注时放大镜跟着弹（用户 11-18 撤的就是这个）。
        isDraggingSelection = true
        if let sel = selection {
            selectionDragBaseline = (sel, document?.elements ?? [])
            v070Frames = 0; v070Fractional = 0; v070Unpaired = 0; v070RowChanges = 0; v070LastRow = nil; v070CoverChanges = 0; v070WasCovered = nil; v070Anchor = nil
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
        // 拖拽期间系统不再发 mouseMoved，锚点必须在这里跟着鼠标走：否则放大镜停在"最后一次悬停的位置"，
        // 放大的是别处的像素（用户 11-18 那张截图里，读数条就是半路停着的）。
        loupeAnchor = p
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
        logDragGeometryCheck()
        isDraggingSelection = false
        selectionDragBaseline = nil
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

    /// 把设置里的默认样式装进视图。会话在建遮罩窗后立刻调一次（`MSSessionCoordinator`）。
    public func applyDefaults(_ spec: MSAnnotationStyleSpec) {
        if MSColorRGBA(hex: spec.strokeHex) != nil { colorHex = spec.strokeHex }
        lineWidth = spec.lineWidth
        fontSize = spec.fontSize
        blurRadius = spec.blurRadius
        MSLog.info(.annotate, "annotation defaults applied stroke=\(self.colorHex) width=\(self.lineWidth) "
                   + "font=\(self.fontSize) blur=\(self.blurRadius)")
    }

    private func currentStyle() -> MSAnnotationStyle {
        var s = MSAnnotationStyle(stroke: MSColorRGBA(hex: colorHex) ?? .rgb(232, 51, 71), lineWidth: lineWidth)
        s.blurRadius = blurRadius
        s.fontSize = fontSize
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
        case 8 where !flags.contains(.command):                            // C / ⇧C（放大镜取色）
            guard let host else { return false }
            if flags.contains(.shift) { cycleLoupeFormat(); needsDisplay = true }
            else { delegate?.overlay(host, didPickColor: loupeCopyString()) }
            return true

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

