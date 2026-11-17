import CoreGraphics
import MSAnnotate
import Testing
@testable import MSOverlay

/// 工具条的几何真源。B-025 原本写的是"窄选区会丢按钮"，实测更准的说法是：
/// 条宽跟**屏宽**走而不是选区宽，所以窄选区不丢按钮，但**贴右边会把整条推出屏幕**；
/// 真正会丢内容的是屏宽 < 650 的极窄屏。这里把三种情况都钉住。
struct ToolbarLayoutTests {
    private let tools = MSTool.allCases
    private let colors = ["#E83347", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#AF52DE"]
    private var fullHD: CGRect { CGRect(x: 0, y: 0, width: 1920, height: 1080) }

    @Test("自然宽度：10 工具 + 6 色 + 键位提示")
    func naturalWidthIsExplicit() {
        // 实测值：8 内边距 + 10×28 工具 + 8 组间距 + 6×18 色 + 250 提示文字。
        // 旧公式算出 638 是因为两侧内边距没算进去——数值以这里为准，别照抄旧稿。
        #expect(MSOverlayToolbar.naturalWidth(toolCount: 10, colorCount: 6, showsActions: true) == 654)
        #expect(MSOverlayToolbar.naturalWidth(toolCount: 10, colorCount: 6, showsActions: false) == 404)
    }

    @Test("窄选区不丢按钮：条宽跟内容走，跟选区无关")
    func narrowSelectionKeepsEveryTool() {
        for w in [60.0, 120.0, 320.0, 640.0] {
            let l = MSOverlayToolbar.layout(selection: CGRect(x: 100, y: 300, width: w, height: 200),
                                            bounds: fullHD, tools: tools, colors: colors)
            #expect(l.toolBoxes.count == tools.count, "选区宽 \(w) 时工具数不该变")
            #expect(l.colorBoxes.count == colors.count)
            #expect(l.showsActions, "1920 屏上键位提示不该被收掉")
        }
    }

    @Test("贴右边的选区：整条必须留在屏内（这就是 B-025 抓到的真缺陷）")
    func barNeverLeaksOffTheRightEdge() {
        for x in [1200.0, 1500.0, 1850.0, 1910.0] {
            let l = MSOverlayToolbar.layout(selection: CGRect(x: x, y: 400, width: 60, height: 100),
                                            bounds: fullHD, tools: tools, colors: colors)
            #expect(l.rect.maxX <= fullHD.maxX - MSOverlayToolbar.screenMargin + 0.001,
                    "x=\(x) 时条子溢出到 \(l.rect.maxX)")
            #expect(l.rect.minX >= fullHD.minX + MSOverlayToolbar.screenMargin)
            // 每个格子都还在条内 ⇒ 不存在"画不出但点得到"
            for (_, box) in l.toolBoxes { #expect(l.rect.contains(box.insetBy(dx: -0.5, dy: -0.5))) }
        }
    }

    @Test("贴顶的选区：条子翻到选区下方，不许被推出上边界")
    func barFlipsBelowWhenThereIsNoRoomAbove() {
        let sel = CGRect(x: 200, y: 1080 - 40, width: 300, height: 30)   // 视图 y 向上：贴着屏顶
        let l = MSOverlayToolbar.layout(selection: sel, bounds: fullHD, tools: tools, colors: colors)
        #expect(l.rect.maxY < sel.minY, "放不下就翻到选区下面")
        let top = CGRect(x: 200, y: 20, width: 300, height: 300)         // 贴屏底（视图 y 小）
        let above = MSOverlayToolbar.layout(selection: top, bounds: fullHD, tools: tools, colors: colors)
        #expect(above.rect.minY >= fullHD.minY + MSOverlayToolbar.screenMargin)
    }

    @Test("极窄屏：先收键位提示文字，工具一个都不能少")
    func narrowDisplayDropsActionsFirst() {
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let l = MSOverlayToolbar.layout(selection: CGRect(x: 10, y: 100, width: 200, height: 100),
                                        bounds: small, tools: tools, colors: colors)
        #expect(!l.showsActions, "600pt 屏放不下 638pt ⇒ 收掉提示文字")
        #expect(l.toolBoxes.count == tools.count, "收的是文字，不是工具")
        #expect(l.rect.maxX <= small.maxX - MSOverlayToolbar.screenMargin + 0.001)
    }

    @Test("绘制顺序即命中顺序：格子不重叠、按工具表排列")
    func boxesAreOrderedAndDisjoint() {
        let l = MSOverlayToolbar.layout(selection: CGRect(x: 300, y: 300, width: 400, height: 300),
                                        bounds: fullHD, tools: tools, colors: colors)
        #expect(l.toolBoxes.map(\.0) == tools)
        for i in 0..<l.toolBoxes.count {
            for k in (i + 1)..<l.toolBoxes.count {
                #expect(l.toolBoxes[i].1.intersection(l.toolBoxes[k].1).isEmpty, "工具格重叠")
            }
        }
        for (_, box) in l.colorBoxes { #expect(l.rect.contains(box)) }
    }

    @Test("尺寸读数：外侧被工具条占住就翻内侧（实拍抓到的遮挡）")
    func readoutFlipsInsideWhenToolbarBlocks() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let sel = CGRect(x: 700, y: 400, width: 420, height: 260)
        let size = CGSize(width: 90, height: 18)
        let bar = MSOverlayToolbar.layout(selection: sel, bounds: bounds, tools: tools, colors: colors)

        let free = MSOverlayToolbar.readoutOrigin(selection: sel, bounds: bounds, readoutSize: size, toolbar: nil)
        #expect(abs(free.y - (sel.minY - size.height - 8)) < 0.001, "没工具条时走右下外侧")
        #expect(free.y < sel.minY)

        let blocked = MSOverlayToolbar.readoutOrigin(selection: sel, bounds: bounds, readoutSize: size, toolbar: bar.rect)
        #expect(blocked.y > sel.minY, "外侧被占 ⇒ 翻内侧（实测 \(blocked.y) vs \(sel.minY)）")
        #expect(abs(blocked.x + size.width - (sel.maxX - 8)) < 0.001, "内侧仍贴右下")

        // 选区贴屏底：外侧会掉出屏幕，也必须翻内侧
        let low = CGRect(x: 700, y: 12, width: 420, height: 200)
        let atBottom = MSOverlayToolbar.readoutOrigin(selection: low, bounds: bounds, readoutSize: size, toolbar: nil)
        #expect(atBottom.y > low.minY, "贴屏底时外侧越界 ⇒ 内侧")

        // 贴右边的选区：x 必须被钳在屏内
        let right = CGRect(x: 1860, y: 400, width: 50, height: 200)
        let clamped = MSOverlayToolbar.readoutOrigin(selection: right, bounds: bounds, readoutSize: size, toolbar: nil)
        #expect(clamped.x + size.width <= bounds.maxX - MSOverlayToolbar.screenMargin + 0.001)
    }
}
