import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSPin

/// `M-4` 准出③：`E` 进编辑 → 画箭头 → `Enter` 退出 → **同一张贴图**含箭头且 `elements.count` +1。
/// 这是 `D-04`（贴图携带可编辑文档）的真验收：如果只能重画不能改，那条决策就没有兑现。
///
/// `MSPin` 此前一个测试都没有，所以"`activeTool` 从没被任何代码赋值 ⇒ 再编辑态画不出东西"
/// 这种问题一直没人发现（`E-055`）。判据一律走合成事件喂真实 `keyDown/mouseDown/…`。
struct PinEditLoopTests {
    private static let screenHeight = NSScreen.screens.first?.frame.height ?? 1080

    private func key(_ code: UInt16, _ chars: String, _ flags: CGEventFlags = []) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)!
        cg.flags = flags
        return NSEvent(cgEvent: cg)!
    }

    private func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(mouseEventSource: src, mouseType: type,
                         mouseCursorPosition: CGPoint(x: p.x, y: Self.screenHeight - p.y), mouseButton: .left)!
        return NSEvent(cgEvent: cg)!
    }

    /// 默认 200×140 逻辑点（画布 400×280 @2x）。工具条自然宽 404pt，
    /// 所以这个尺寸**放不下工具条**，走字母兜底——这是当前已知形态缺口（`B-028`），
    /// 不是测试写错：宽贴图（≥412pt）才用 `makePin(width:height:)` 造。
    @MainActor
    private func makePin() -> (MSPinWindow, MSPinView) { makePin(width: 200, height: 140) }

    @MainActor
    private func makePin(width: Int, height: Int) -> (MSPinWindow, MSPinView) {
        let ctx = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(120, 160, 200).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width * 2, height: height * 2))
        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: width * 2, height: height * 2)),
                                   source: ctx.makeImage()!, scale: 2)
        let window = MSPinWindow(content: content, origin: NSPoint(x: 100, y: 100), menu: nil)
        return (window, window.pinView)
    }

    @MainActor
    @Test("E 进编辑 → 画箭头 → Enter 退出：同一贴图元素 +1")
    func fullEditLoopAddsElementToSamePin() throws {
        let (window, view) = makePin()
        let docIDBefore = view.content.document.elements.count
        #expect(!view.isEditing)

        view.keyDown(with: key(14, "e"))                      // E：进编辑
        #expect(view.isEditing, "E 该进入再编辑态")

        view.keyDown(with: key(0, "a"))                       // A：箭头工具
        #expect(view.activeTool == .arrow, "字母必须真能选到工具（此前 activeTool 没人赋值，画不出东西）")

        let from = CGPoint(x: 40, y: 100), to = CGPoint(x: 150, y: 40)
        view.mouseDown(with: mouse(.leftMouseDown, from))
        view.mouseDragged(with: mouse(.leftMouseDragged, to))
        view.mouseUp(with: mouse(.leftMouseUp, to))

        view.keyDown(with: key(36, "\r"))                     // Enter：退出编辑
        #expect(!view.isEditing)

        let elements = view.content.document.elements
        #expect(elements.count == docIDBefore + 1, "同一份文档必须真的多了一个元素")
        #expect(elements.first?.kind == .arrow)
        #expect(elements.first?.points.count == 2)
    }

    @MainActor
    @Test("工具条：点格子选工具，且不会误画一个元素")
    func toolbarClickSelectsToolWithoutDrawing() throws {
        let (window, view) = makePin(width: 620, height: 400)   // 404pt 工具条要够宽才画得下
        view.isEditing = true
        view.activeTool = .rect
        // 触发一次绘制以算出布局（布局在 draw 里算）
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        if let rep { view.cacheDisplay(in: view.bounds, to: rep) }
        let layout = try #require(view.editToolbarLayout, "620pt 宽的贴图该放得下 404pt 工具条")

        let arrowBox = try #require(layout.items.first { $0.0 == .arrow }?.1)
        let before = view.content.document.elements.count
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: arrowBox.midX, y: arrowBox.midY)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: arrowBox.midX, y: arrowBox.midY)))
        #expect(view.activeTool == .arrow, "点工具格＝选工具")
        #expect(view.content.document.elements.count == before, "点工具格不该顺手画出一个元素")
    }

    @MainActor
    @Test("编辑态 E 归橡皮擦，退出只用 Enter/Esc（keymap §4 的上下文优先级）")
    func eKeyIsEraserWhileEditing() throws {
        let (_, view) = makePin()
        view.keyDown(with: key(14, "e"))
        #expect(view.isEditing)
        view.keyDown(with: key(14, "e"))                       // 编辑态再按 E
        #expect(view.isEditing, "编辑态里 E 不该退出")
        #expect(view.activeTool == .eraser, "E 在编辑态＝橡皮擦")
        view.keyDown(with: key(53, "\u{1b}"))                 // Esc 退出
        #expect(!view.isEditing)
    }

    @MainActor
    @Test("没选工具时按下拖动是移窗，不产生元素")
    func noToolMeansWindowDrag() throws {
        let (window, view) = makePin()
        view.isEditing = true
        view.activeTool = nil
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 60, y: 60)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 90, y: 90)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 90, y: 90)))
        #expect(view.content.document.elements.isEmpty, "选择工具下不许落元素")
    }

    @MainActor
    @Test("撤销栈属于贴图：⌘Z 撤掉刚画的箭头")
    func undoIsScopedToThisPin() throws {
        let (window, view) = makePin()
        view.isEditing = true
        view.activeTool = .rect
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 30, y: 110)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 120, y: 40)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 120, y: 40)))
        #expect(view.content.document.elements.count == 1)
        view.keyDown(with: key(6, "z", .maskCommand))          // ⌘Z
        #expect(view.content.document.elements.isEmpty, "贴图自己的撤销栈必须管得住自己的绘制")
    }

    @MainActor
    @Test("窄贴图放不下工具条时，字母仍可选工具")
    func narrowPinFallsBackToKeyboard() throws {
        let ctx = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(200, 200, 200).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: 120, height: 80)),
                                   source: ctx.makeImage()!, scale: 1)
        let window = MSPinWindow(content: content, origin: nil, menu: nil)
        let view = window.pinView
        view.isEditing = true
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        #expect(view.editToolbarLayout == nil, "60×40 的贴图确实放不下工具条（B-028 记录的形态缺口）")
        view.keyDown(with: key(0, "a"))
        #expect(view.activeTool == .arrow, "工具条缺席时字母必须还能用，否则小贴图根本没法再编辑")
    }
}
