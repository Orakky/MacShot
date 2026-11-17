import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSPin

/// `B-028`（11-17 裁"折两行"）的实现与其**实测边界**。
///
/// 算术前先看数字（`flowNumbers` 会把它们钉住，行高 34、格宽 28、色板独占最后一行）：
///
/// | 贴图 | 每行格数 | 总行 | 需要高 | 占画面 | 结论 |
/// |---|---|---|---|---|---|
/// | 620×400 | 21 | 2 | 70pt | 17% | 放得下 |
/// | 288×200 | 9 | 3 | 106pt | 53% | 放得下（已经很挤） |
/// | **200×140** | 6 | 3 | 106pt | **75%** | **放不下**（预算 60%） |
/// | 60×40 | 1 | 11 | 394pt | 985% | 荒谬，只能字母兜底 |
///
/// ⇒ 折行**救不了它本来想救的那类小贴图**。这不是实现 bug，是方案本身的几何极限，
/// 已如实回写 `blocked.md B-028` 等用户在"撑高贴图窗（图片不被盖住）"与"接受覆盖上限"之间选。
struct ToolbarFlowTests {
    private func pin(width: Int, height: Int) -> MSPinView {
        let ctx = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(150, 150, 150).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width * 2, height: height * 2))
        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: width * 2, height: height * 2)),
                                   source: ctx.makeImage()!, scale: 2)
        return MSPinWindow(content: content, origin: nil, menu: nil).pinView
    }

    @Test("折行的算术边界被钉住：宽贴图放得下、200×140 放不下")
    func flowNumbers() {
        let tools = MSPinView.pinToolbarTools.count
        func rows(width: Double, height: Double) -> (fits: Bool, need: Double, perRow: Int) {
            guard let flow = MSAnnotationToolbar.flow(toolCount: tools, colorCount: MSAnnotationPalette.toolbar.count,
                                                      maxWidth: width - 8, maxHeight: height * 0.6) else {
                let perRow = max(1, Int(((width - 16 + 2) / 28).rounded(.down)))
                let r = (tools + perRow - 1) / perRow + 1
                return (false, Double(r) * 34 + Double(r - 1) * 2, perRow)
            }
            let perRow = max(1, Int(((width - 16 + 2) / 28).rounded(.down)))
            return (true, flow.rect.height, perRow)
        }
        #expect(rows(width: 620, height: 400).fits)
        #expect(rows(width: 288, height: 200).fits, "53% 覆盖虽然挤，但确实放得下")
        #expect(!rows(width: 200, height: 140).fits, "200×140 需要 106pt=75% 画面 ⇒ 必须判为放不下")
        #expect(!rows(width: 60, height: 40).fits)
    }

    @MainActor
    @Test("放得下时：全部工具与色都在视图内、互不重叠、格子真画得出东西")
    func widePinGetsFullToolbar() throws {
        let view = pin(width: 620, height: 400)
        view.isEditing = false
        guard let plain = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: view.bounds, to: plain)
        view.isEditing = true
        guard let marked = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: view.bounds, to: marked)

        let layout = try #require(view.editToolbarLayout)
        #expect(layout.items.count == MSPinView.pinToolbarTools.count, "不许静默少画工具")
        #expect(layout.colors.count == MSAnnotationPalette.toolbar.count)
        for (_, box) in layout.items { #expect(view.bounds.contains(box.insetBy(dx: -0.5, dy: -0.5)), "工具格出界 \(box)") }
        for i in 0..<layout.items.count {
            for j in (i + 1)..<layout.items.count {
                #expect(layout.items[i].1.intersection(layout.items[j].1).isEmpty, "格子重叠＝命中会选错")
            }
        }
        // V-044 纪律：算出位置不等于画出来了，逐格量墨
        let scale = CGFloat(marked.pixelsWide) / view.bounds.width
        // 视图 y 向上、位图行号向下：必须换算，否则量到的是镜像位置。
        // （这一行我自己写反过一次，量出来是"10 个格子都没画"——其实是尺放错了地方。）
        func rows(of box: CGRect) -> (Int, Int) {
            (Int((view.bounds.height - box.maxY) * scale), Int((view.bounds.height - box.minY) * scale))
        }
        var emptyCells = 0
        for (_, box) in layout.items {
            var ink = 0
            let (r0, r1) = rows(of: box)
            for y in stride(from: r0, to: min(r1, marked.pixelsHigh), by: 2) {
                for x in stride(from: Int(box.minX * scale), to: Int(box.maxX * scale), by: 2) {
                    guard let a = plain.colorAt(x: x, y: y), let b = marked.colorAt(x: x, y: y) else { continue }
                    if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                        + abs(a.blueComponent - b.blueComponent) > 0.2 { ink += 1 }
                }
            }
            if ink == 0 { emptyCells += 1 }
        }
        #expect(emptyCells == 0, "\(emptyCells) 个格子算出了位置却什么都没画")
    }

    @MainActor
    @Test("最后一行的格子点得到（绘制与命中同一份格子）")
    func lastRowIsClickable() throws {
        let view = pin(width: 620, height: 400)
        view.isEditing = true
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        let layout = try #require(view.editToolbarLayout)
        let last = layout.items[layout.items.count - 1]
        let src = CGEventSource(stateID: .combinedSessionState)
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let point = CGPoint(x: last.1.midX, y: last.1.midY)
        let cg = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                         mouseCursorPosition: CGPoint(x: point.x, y: realHeight - point.y), mouseButton: .left)!
        view.mouseDown(with: NSEvent(cgEvent: cg)!)
        #expect(view.activeTool == last.0, "最后一行的 \(last.0) 点不到 ⇒ 画在那儿但点不着")
    }

    @MainActor
    @Test("200×140 这类小贴图：折行也放不下 ⇒ 不画工具条，但字母必须仍可用")
    func smallPinFallsBackHonestly() throws {
        let view = pin(width: 200, height: 140)
        view.isEditing = true
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        #expect(view.editToolbarLayout == nil, "覆盖 75% 画面的工具条比没有工具条更糟")
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)!
        view.keyDown(with: NSEvent(cgEvent: cg)!)
        #expect(view.activeTool == .arrow, "工具条缺席时字母必须还能用")
    }
}
