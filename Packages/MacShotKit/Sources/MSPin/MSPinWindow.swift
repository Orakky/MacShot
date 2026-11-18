import AppKit
import Darwin
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
    /// 编辑态在图片**下方**多出来的一条工具带高度（0 = 非编辑态，或这张贴图小到放不下工具条）。
    /// 关键约束：图片区域永远是 `imageRect`，工具带绝不进图片——导出走渲染器与窗口无关
    /// （`FR-EXP-002`），所以这条带子不可能污染导出像素。
    /// 11-17 走过折行方案，实测 200×140 的贴图要盖掉 75% 画面，于是改成撑高窗口（`B-028`）。
    public private(set) var stripHeight: CGFloat = 0

    /// 图片实际占据的矩形（视图坐标，y 向上：底部让给工具带）。
    public var imageRect: CGRect {
        CGRect(x: 0, y: stripHeight, width: bounds.width, height: max(1, bounds.height - stripHeight))
    }

    public var isEditing = false { didSet { if oldValue != isEditing { applyStrip() } } }
    // 顺序有讲究：applyStrip 读的是 bounds.width，必须先让窗口按新 zoom 长缩，再重算工具带。
    public var zoom: CGFloat = 1 { didSet { resizeWindow(); applyStrip(); needsDisplay = true } }
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
        // 图片尺寸 + 编辑态工具带；工具带长在下方，所以顶边不动（与 zoom 同一套锚定规则）
        let size = CGSize(width: content.logicalSize.width * zoom,
                          height: content.logicalSize.height * zoom + stripHeight)
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
        ctx.draw(content.source, in: imageRect)          // 图片只画在 imageRect，工具带不吃画面
        ctx.restoreGState()

        // 2) vector layer: one unit = one canvas pixel, scaled up to the view. AppKit's context is
        //    already in backing-store pixels, so strokes stay crisp at any zoom.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: stripHeight)           // 矢量层与位图必须落在同一个矩形里
        ctx.scaleBy(x: imageRect.width / docW, y: imageRect.width / docW)
        renderer.renderElements(of: content.document, into: ctx, source: content.source,
                               canvas: docSize, intent: .pin)
        if let draft { renderer.renderElements(of: draftDocument(draft), into: ctx, source: content.source,
                                              canvas: docSize, intent: .preview) }
        ctx.restoreGState()

        if isEditing { drawEditModeChrome(); drawEditToolbar() }
        drawBadge()
    }

    private func draftDocument(_ element: MSAnnotationElement) -> MSAnnotationDocument {
        var doc = content.document
        doc.elements = [element]
        return doc
    }

    /// 编辑态工具条的实测布局：钉在贴图**下沿内侧**。窄到放不下工具格时返回 nil，
    /// 此时只能用字母选工具（小贴图上的形态规格未定，已开卡点）。
    struct EditToolbarLayout {   // internal：测试要能读到格子位置，绘制与命中才不会被各自发明
        let rect: CGRect
        let items: [(MSTool, CGRect)]
        let colors: [CGRect]
    }

    /// 贴图编辑态可用的工具：先排除 `text`——这里没有 field editor，接进工具条只会
    /// 落下一个空文本元素（半个实现比不接更坏）。文字在贴图里的再编辑另批做。
    static let pinToolbarTools: [MSTool] = MSTool.allCases.filter { $0 != .text }

    private(set) var editToolbarLayout: EditToolbarLayout?

    /// 贴图编辑态工具条：长在图片**下方**的工具带里（`B-028` 定稿＝撑高窗，形态见 `UI-004`）；
    /// 带内格子放不下时按宽度分多行，连预算都不够才退回字母兜底。
    /// 极小贴图（比如 60×40）确实放不下 10 个工具格——那是几何事实，不硬塞、不静默少画。
    /// 重算工具带高度并让窗口跟着长/缩。预算 = min(160pt, 图片高)：
    /// 工具带本身不该比图片还高，超了就退回字母兜底（`60×40` 这类）。
    private func applyStrip() {
        guard isEditing else {
            if stripHeight != 0 { stripHeight = 0; resizeWindow(); needsDisplay = true }
            return
        }
        let tools = Self.pinToolbarTools
        let imageHeight = content.logicalSize.height * zoom
        let budget = min(160, imageHeight)
        guard let flow = MSAnnotationToolbar.flow(toolCount: tools.count,
                                                  colorCount: MSAnnotationPalette.toolbar.count,
                                                  maxWidth: bounds.width - 8, maxHeight: budget) else {
            if stripHeight != 0 { stripHeight = 0; resizeWindow(); needsDisplay = true }
            return
        }
        let needed = flow.rect.height + 8
        if abs(needed - stripHeight) > 0.5 {
            stripHeight = needed
            resizeWindow()
        }
        needsDisplay = true
    }

    /// 工具带内的格子布局（flow 的局部坐标平移到视图底部）。
    private func computeEditToolbar() -> EditToolbarLayout? {

        let tools = Self.pinToolbarTools
        guard stripHeight > 0, let flow = MSAnnotationToolbar.flow(toolCount: tools.count,
                                                  colorCount: MSAnnotationPalette.toolbar.count,
                                                  maxWidth: bounds.width - 8,
                                                  maxHeight: stripHeight) else { return nil }
        // flow 给的是"以 0 为原点"的局部格子，整体平移到视图底部的工具带里
        let origin = CGPoint(x: (bounds.width - flow.rect.width) / 2, y: bounds.minY + 4)
        let move: (CGRect) -> CGRect = { $0.offsetBy(dx: origin.x, dy: origin.y) }
        return EditToolbarLayout(rect: move(flow.rect),
                                 items: Array(zip(tools, flow.toolBoxes.map(move))),
                                 colors: flow.colorBoxes.map(move))
    }

    /// `UI-004`：编辑态必须看得见"正在编辑"和"能选工具"。画不出这两样，再编辑就等于隐藏功能。
    private func drawEditToolbar() {
        guard let layout = computeEditToolbar() else {
            NSAttributedString(string: " ✎ 编辑中 · 按字母选工具（M/O/A/L/P/H/T/N/B）· Enter/Esc 退出 ", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7),
            ]).draw(at: NSPoint(x: 6, y: bounds.maxY - 22))
            return
        }
        editToolbarLayout = layout
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        let path = NSBezierPath(roundedRect: layout.rect, xRadius: 8, yRadius: 8)
        path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 1; path.stroke()
        for (tool, box) in layout.items {
            if tool == activeTool {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                box.fill()
            }
            if !MSPinIcons.draw(tool, in: box, tint: tool == activeTool ? .controlAccentColor : .labelColor) {
                NSAttributedString(string: tool.letter, attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
                ]).draw(at: NSPoint(x: box.midX - 4, y: box.midY - 8))
            }
        }
        for (index, box) in layout.colors.enumerated() {
            let swatch = MSColorRGBA(hex: MSAnnotationPalette.toolbar[index]) ?? .rgb(255, 0, 0)
            if let ns = NSColor(cgColor: swatch.cgColor) { ns.setFill() } else { NSColor.red.setFill() }
            NSBezierPath(ovalIn: box).fill()
            if MSColorRGBA(hex: MSAnnotationPalette.toolbar[index]) == content.document.currentStyle.stroke {
                NSColor.controlAccentColor.setStroke()
                let ring = NSBezierPath(ovalIn: box.insetBy(dx: -2, dy: -2)); ring.lineWidth = 2; ring.stroke()
            }
        }
        ctx?.restoreGState()
        NSAttributedString(string: " ✎ 编辑中 ", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.9),
        ]).draw(at: NSPoint(x: 6, y: bounds.maxY - 22))
    }

    private func drawEditModeChrome() {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath(rect: imageRect.insetBy(dx: 0.5, dy: 0.5))
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
        s.draw(at: NSPoint(x: imageRect.maxX - size.width - 6, y: imageRect.maxY - size.height - 6))
    }

    private var hasExportedFlag: Bool { window is MSPinWindow ? (window as? MSPinWindow)?.hasExported ?? true : true }

    // MARK: - editing (same document object, not a copy)

    /// 编辑态当前工具，与遮罩共用同一张 `MSTool` 表（`UI-004` 要求"UI-002 同款工具条"）。
    /// nil = 选择工具：此时按下拖动是移窗，不是画标注。
    public var activeTool: MSTool?

    public override func mouseDown(with event: NSEvent) {
        guard isEditing else { super.mouseDown(with: event); return }
        let viewP = convert(event.locationInWindow, from: nil)
        // 工具条优先：点格子是选工具，不该被当成"在画布上落笔"
        if let layout = editToolbarLayout {
            if let (tool, _) = layout.items.first(where: { $0.1.contains(viewP) }) {
                activeTool = tool
                MSLog.info(.pin, "edit tool=\(tool.rawValue)")
                return
            }
            if let (index, box) = layout.colors.enumerated().first(where: { $0.element.insetBy(dx: -3, dy: -3).contains(viewP) }) {
                var style = content.document.currentStyle
                style.stroke = MSColorRGBA(hex: MSAnnotationPalette.toolbar[index]) ?? style.stroke
                content.document.currentStyle = style
                MSLog.info(.pin, "edit color=\(index)")
                return
            }
        }
        guard let tool = activeTool, let kind = tool.annotationKind else { super.mouseDown(with: event); return }
        let p = docPoint(viewP)
        // 旧代码这里写着 `tool != .eraser` 当守卫，于是 eraser 分支永远走不到——
        // 橡皮擦在贴图里点了只会拖窗。点击动作统一交给 performClickAction。
        if tool.isClickAction { performClickAction(tool: tool, at: p); return }
        draft = MSAnnotationElement(kind: kind, points: [p, p], style: content.document.currentStyle,
                                   text: kind == .badge ? content.document.nextBadgeText : "",
                                   variant: kind == .freehand && tool.isFreehandPen ? "pen" : nil)
    }

    /// `N` 序号 / `E` 橡皮擦：一次动作一条撤销记录，与遮罩里同一套语义（`annotate-model.md` §4）。
    func performClickAction(tool: MSTool, at p: MSIntPoint) {
        var doc = content.document
        switch tool {
        case .badge:
            let before = doc.badgeCounter
            let element = MSAnnotationElement(kind: .badge, points: [p], style: doc.currentStyle, text: String(before))
            history.apply(.composite([.insert(element), .badgeCounter(before: before, after: before + 1)]), to: &doc)
        case .eraser:
            let target = CGPoint(x: p.x, y: p.y)
            guard let hit = doc.sortedElements.reversed().first(where: {
                MSAnnotationGeometry.hitTest(target, element: $0, extraTolerance: 4)
            }) else {
                MSLog.debug(.pin, "eraser 没命中任何元素")
                return
            }
            history.apply(.remove(hit), to: &doc)
        default:
            return
        }
        content.document = doc
        (window as? MSPinWindow)?.markDirty()
        needsDisplay = true
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

    /// 视图点（y 向上）→ 画布像素（y 向下）：这个视图里唯一一次换算。
    /// 必须走 `imageRect` 而不是 `bounds`——工具带在下方，用 bounds 会把画面纵向拉长，
    /// 于是"点在哪就画在哪"变成"越靠下越偏"（internal 是给测试直接喂坐标）。
    func docPoint(_ p: NSPoint) -> MSIntPoint {
        let doc = content.document.canvasSize
        let image = imageRect
        let x = (p.x - image.minX) / max(1, image.width) * CGFloat(doc.width)
        let y = (image.maxY - p.y) / max(1, image.height) * CGFloat(doc.height)
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
        if isEditing, !flags.contains(.command) {
            // `UI-004`：退出编辑 = Enter / Esc（`E` 在编辑态归橡皮擦，见 keymap §4 的上下文优先级）
            // 写成成员判断而不是 switch：门禁禁 `default: break`（规范 §4b，B-018 就是被它吞掉的）
            if [53, 36, 76].contains(Int(event.keyCode)) {
                onAction?(.toggleEdit)
                return
            }
            if let ch = event.charactersIgnoringModifiers?.lowercased(),
               let tool = Self.pinToolbarTools.first(where: { $0.letter.lowercased() == ch }) {
                activeTool = tool
                MSLog.info(.pin, "edit tool=\(tool.rawValue) via key")
                return
            }
        }
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

    /// 贴图全部关掉后压一次分配器：macOS 的 malloc 不会主动把空页交还系统，于是 RSS 停在高位。
    /// `E-072` 实测 10 张 4K 贴图关闭后残留 +32.9MB（RSS 口径破 `NFR-008` 的 ±10%），
    /// 压一次回到 +1.9MB；而**两轮批次峰值只差 1.2MB**，证明那 33MB 本来就是可复用的缓存、
    /// 不是泄漏——所以这里要的是"把缓存还给系统"，不是"改需求定义"。
    private func releaseMemoryIfEmpty() {
        guard count == 0 else { return }
        malloc_zone_pressure_relief(nil, 0)
        MSLog.info(.pin, "allocator pressure relief (no pins left)")
    }

    private func remove(_ pin: MSPinWindow) {
        lock.withLock { pins.removeAll { $0 === pin } }
        MSLog.info(.pin, "closed, remaining=\(self.count)")
        releaseMemoryIfEmpty()
    }

    public func closeAll(askUser: Bool = false) {
        let list = lock.withLock { pins }
        for pin in list { pin.close() }
        lock.withLock { pins.removeAll() }
        MSLog.info(.pin, "closed all (\(list.count))")
        releaseMemoryIfEmpty()
        _ = askUser
    }

    /// Bring a pin back on-screen after a display change (`pin-window.md` §9).
    public func reanchorAll(to screen: NSScreen?) {
        all.forEach { $0.resetOrigin(for: screen) }
    }
}
