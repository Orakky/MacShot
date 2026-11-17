import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSOverlay

/// `FR-ANN-004` 的选中/移动/层级 + `M-4` 准出②「拖 100 次 → 撤销栈 1 条」。
/// 判据一律走真实事件链：合成鼠标事件喂 `mouseDown/mouseDragged/mouseUp`，
/// 而不是调私有方法——绕开入口的测试拦不住入口上的 bug（今天已经栽过三回）。
///
/// 坐标一律从 `view.selection!` 与 `display.scale` **导出**（用 MSCore 那对正反换算），
/// 不手写数字：上一版手写了 800×500 画布，而 `setSelection` 按真实像素换成 760×460，
/// 于是文档被替换、坐标全错位——测试红得莫名其妙就是这个样子。
struct ElementSelectionTests {
    private static let display = MSTestCard.display          // 400×250 逻辑点，scale 2

    private func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        // 视图点（y 向上）→ CGEvent 全局坐标（y 向下）；窗就是整屏，原点 0
        // CGEvent 的全局 y 是**真实主屏**自上而下算的，`NSEvent.locationInWindow` 再由它反推。
        // 上一版用假显示器的 250 去除，点全落到视图外：选中失败 → 选区被清空 → 后续强解包崩。
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let flipped = CGPoint(x: p.x, y: realHeight - p.y)
        let cg = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: flipped, mouseButton: .left)!
        return NSEvent(cgEvent: cg)!
    }

    private func kb(_ code: UInt16, _ flags: CGEventFlags = []) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)!
        cg.flags = flags
        return NSEvent(cgEvent: cg)!
    }

    /// 先定选区再塞元素：`setSelection` 会按显示器的真实像素建/换文档，
    /// 顺序反了就会被静默替换掉（上一版就是这么把文档弄空的）。
    @MainActor
    private func makeView(elements: [MSAnnotationElement]) throws -> MSOverlayView {
        let ctx = CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let view = MSOverlayView(display: Self.display, frozenFrame: ctx.makeImage()!)
        view.setSelection(CGRect(x: 10, y: 10, width: 380, height: 230))
        var doc = try #require(view.document, "setSelection 之后文档应已按真实像素建好")
        for e in elements { doc.elements.append(e) }
        view.document = doc
        view.tool = .select
        return view
    }

    /// 视图点 ← 画布点（用真源换算，别手算）
    @MainActor
    private func viewPoint(_ view: MSOverlayView, canvas: MSIntPoint) -> CGPoint {
        canvas.viewPoint(in: view.selection!, scale: Self.display.scale)
    }

    private func filledRect(_ a: MSIntPoint, _ b: MSIntPoint, z: Int) -> MSAnnotationElement {
        var style = MSAnnotationStyle.standard
        style.fill = .rgba(232, 51, 71, 0.4)
        return MSAnnotationElement(kind: .rect, points: [a, b], style: style, z: z)
    }

    @MainActor
    @Test("重叠时选中最上层（z 最大），而不是数组里最后那个")
    func hitPicksTopmost() throws {
        let bottom = filledRect(MSIntPoint(x: 20, y: 20), MSIntPoint(x: 300, y: 300), z: 0)
        let top = filledRect(MSIntPoint(x: 100, y: 100), MSIntPoint(x: 200, y: 200), z: 5)
        let view = try makeView(elements: [bottom, top])
        let p = viewPoint(view, canvas: MSIntPoint(x: 150, y: 150))
        let dp = view.docPoint(p, in: view.selection!)
        #expect(dp == MSIntPoint(x: 150, y: 150), "换算必须自洽，否则下面的结论都不可信")
        #expect(view.elementAt(dp)?.z == 5, "取 z 最大的，不是数组顺序的最后一个")
    }

    @MainActor
    @Test("拖 100 次只留一条撤销记录，undo 一次回到原位")
    func hundredDragsMakeOneRecord() throws {
        // 落点刻意避开左上角 ✕ 的 44pt 命中区（那里按钮优先，见下面那条测试）
        let e = filledRect(MSIntPoint(x: 200, y: 200), MSIntPoint(x: 320, y: 320), z: 0)
        let view = try makeView(elements: [e])
        let start = viewPoint(view, canvas: MSIntPoint(x: 260, y: 260))
        view.mouseDown(with: mouse(.leftMouseDown, start))
        #expect(view.selectedID == e.id, "按下即选中")

        for i in 1...100 {
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: start.x + Double(i) * 0.5,
                                                                     y: start.y - Double(i) * 0.3)))
        }
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: start.x + 50, y: start.y - 30)))

        var doc = view.document
        #expect(doc?.elements.count == 1)
        #expect(doc?.elements.first?.points != e.points, "元素确实被移动了")

        let undid = view.history.undo(&doc!)
        #expect(undid, "拖动必须可撤销")
        #expect(doc?.elements.first?.points == e.points, "一次 undo 回到原位，got=\(doc?.elements.first?.points ?? [])")
        let secondUndo = view.history.undo(&doc!)
        #expect(!secondUndo, "100 次拖动只留了一条记录")
    }

    @MainActor
    @Test("点空白取消选择；Delete 删的是选中元素而不是最上层")
    func clickEmptyClearsAndDeleteTargetsSelection() throws {
        let big = filledRect(MSIntPoint(x: 20, y: 20), MSIntPoint(x: 400, y: 300), z: 9)
        let small = filledRect(MSIntPoint(x: 500, y: 60), MSIntPoint(x: 700, y: 200), z: 1)
        let view = try makeView(elements: [big, small])

        func click(_ canvas: MSIntPoint) {
            let p = viewPoint(view, canvas: canvas)
            view.mouseDown(with: mouse(.leftMouseDown, p))
            view.mouseUp(with: mouse(.leftMouseUp, p))
        }
        click(MSIntPoint(x: 100, y: 100))                    // big 内部（z=9）
        #expect(view.selectedID == big.id)

        click(MSIntPoint(x: 740, y: 440))                    // 选区内、两个元素之外
        #expect(view.selectedID == nil, "点空白要取消选择")

        click(MSIntPoint(x: 600, y: 100))                   // small 内部（z 小）
        #expect(view.selectedID == small.id)
        view.deleteSelectedOrLast()
        let rest = view.document?.elements.map(\.id) ?? []
        #expect(rest == [big.id], "删的是选中的 small，不是 z 最大的 big")
    }

    @MainActor
    @Test("左上角 ✕ 的 44pt 命中区优先于其下的元素（按钮赢，不是元素赢）")
    func cancelButtonWinsOverElementBeneathIt() throws {
        // 元素正好压在 ✕ 下面：画布 (28,28)-(120,120) → 视图 (24,226)-(70,180)，与命中区 (14…58, 192…236) 重叠
        let e = filledRect(MSIntPoint(x: 28, y: 28), MSIntPoint(x: 120, y: 120), z: 3)
        let view = try makeView(elements: [e])
        let p = viewPoint(view, canvas: MSIntPoint(x: 45, y: 45))
        #expect(OverlayChrome.cancelHitRect(in: view.bounds).contains(p), "落点确实该在 ✕ 命中区内，否则这条测试是空的")
        view.mouseDown(with: mouse(.leftMouseDown, p))
        view.mouseUp(with: mouse(.leftMouseUp, p))
        #expect(view.selectedID == nil, "✕ 吃掉这次点击，元素不该被选中")
    }

    /// `V-044` 的纪律用到这里：选中态是**视觉承诺**，所以必须用像素证明它真的画出来了，
    /// 而不是只断言 `selectedID` 有值。
    @MainActor
    @Test("选中态真的画得出来：与未选中相比有墨，且落在元素附近")
    func selectionIsActuallyVisible() throws {
        let e = filledRect(MSIntPoint(x: 200, y: 200), MSIntPoint(x: 320, y: 320), z: 0)
        let view = try makeView(elements: [e])
        func snapshot() -> NSBitmapImageRep? {
            view.needsDisplay = true
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        view.selectedID = nil
        guard let bare = snapshot() else { Issue.record("离屏渲染拿不到位图"); return }
        view.selectedID = e.id
        guard let marked = snapshot() else { Issue.record("离屏渲染拿不到位图"); return }

        let scale = CGFloat(marked.pixelsWide) / view.bounds.width
        var differing = 0, minX = marked.pixelsWide, minY = marked.pixelsHigh, maxX = -1, maxY = -1
        for y in stride(from: 0, to: marked.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: marked.pixelsWide, by: 2) {
                guard let a = bare.colorAt(x: x, y: y), let b = marked.colorAt(x: x, y: y) else { continue }
                let d = max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                            abs(a.blueComponent - b.blueComponent))
                if d > 0.12 {
                    differing += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        #expect(differing > 40, "选中后画面必须真的多出一圈东西（实测差异采样点 \(differing)）")
        // 元素画布 (200,200)-(320,320) → 视图 (110,140)-(170,80) → 位图 ×2
        let expected = (x0: Int(110 * scale) - 12, x1: Int(170 * scale) + 12,
                        y0: Int((view.bounds.height - 140) * scale) - 12, y1: Int((view.bounds.height - 80) * scale) + 12)
        #expect(minX >= expected.x0 && maxX <= expected.x1 && minY >= expected.y0 && maxY <= expected.y1,
                "选中框必须套在元素上，got=(\(minX),\(minY))..(\(maxX),\(maxY)) 期望≈\(expected)")
    }

    @MainActor
    @Test("⌘] / ⌘[ 改选中元素的 z；没选中时不动任何东西")
    func layerKeysMoveSelectedElement() throws {
        let a = filledRect(MSIntPoint(x: 20, y: 20), MSIntPoint(x: 100, y: 100), z: 1)
        let b = filledRect(MSIntPoint(x: 200, y: 200), MSIntPoint(x: 300, y: 300), z: 2)
        let view = try makeView(elements: [a, b])
        let zOfA: () -> Int? = { view.document?.elements.first { $0.id == a.id }?.z }

        view.selectedID = a.id
        #expect(view.handleKey(kb(30, .maskCommand)), "⌘] 该被吃掉")
        #expect(zOfA() == 2, "上移一层")
        #expect(view.handleKey(kb(38, .maskCommand)))
        #expect(zOfA() == 1, "下移回来")

        view.selectedID = nil
        view.changeLayer(up: true)
        #expect(view.document?.elements.map(\.z) == [1, 2], "没选中时层级键不许乱改")
    }
}
