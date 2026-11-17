import CoreGraphics
import Foundation

/// 标注工具条的**度量与格子排布**（规格 `design/screens.md#UI-002`）。
///
/// 为什么在 `MSAnnotate` 而不是 `MSOverlay`：遮罩与贴图再编辑态要用**同一条**工具条
/// （`UI-004`："UI-002 同款工具条，钉在贴图下沿"），而 `MSPin` 按依赖方向不许 import
/// `MSOverlay`（`charter.md` §4）。度量只有一个家；**摆在哪**由各表面自己决定并各自测。
public enum MSAnnotationToolbar {
    public static let item: CGFloat = 26
    public static let gap: CGFloat = 2
    public static let height: CGFloat = 34
    public static let edgePad: CGFloat = 4
    public static let colorGroupGap: CGFloat = 8
    public static let colorDot: CGFloat = 14
    public static let colorStep: CGFloat = 18
    public static let actionWidth: CGFloat = 250
    public static let screenMargin: CGFloat = 6
    public static let selectionGap: CGFloat = 6

    /// 内容自然宽度。实测 10 工具 + 6 色 + 提示文字 = 654pt（旧稿 638 少算了两侧内边距）。
    public static func naturalWidth(itemCount: Int, colorCount: Int, showsActions: Bool) -> CGFloat {
        let items = CGFloat(itemCount) * (item + gap)
        let colors = CGFloat(colorCount) * colorStep
        return edgePad * 2 + items + colorGroupGap + colors + (showsActions ? actionWidth : 0)
    }

    /// 屏宽不够时先收掉键位提示文字（它和遮罩底部提示条重复），**不收工具**。
    public static func showsActions(widthAvailable: CGFloat, itemCount: Int, colorCount: Int) -> Bool {
        naturalWidth(itemCount: itemCount, colorCount: colorCount, showsActions: true)
            <= widthAvailable - screenMargin * 2
    }

    /// 给定条的矩形，算出每个工具格与色块的位置。绘制与命中必须共用这一份，
    /// 否则就是"画在一处、点在另一处"（2026-11-16 遮罩 ✕ 的成因）。
    public static func boxes(rect: CGRect, itemCount: Int, colorCount: Int) -> (items: [CGRect], colors: [CGRect]) {
        var items: [CGRect] = []
        var x = rect.minX + edgePad
        for _ in 0..<itemCount {
            items.append(CGRect(x: x, y: rect.minY + 4, width: item, height: item))
            x += item + gap
        }
        var colors: [CGRect] = []
        var cx = x + colorGroupGap - gap
        for _ in 0..<colorCount {
            colors.append(CGRect(x: cx, y: rect.midY - colorDot / 2, width: colorDot, height: colorDot))
            cx += colorStep
        }
        return (items, colors)
    }

    /// 多行（流程）布局：贴图宽度放不下单行时按宽度折行（`B-028` 11-17 裁决）。
    ///
    /// 规则定死，免得每个表面各自发明：一行放 `perRow` 个工具格，工具排满若干行后
    /// **色板独占最后一行**；行高与单行一致，所以两种形态的命中逻辑是同一份代码。
    /// 返回 nil 表示"这个尺寸确实放不下"——调用方必须有兜底（贴图侧是字母选工具），
    /// 不许硬塞到视图外，也不许静默少画几个工具。
    public static func flow(toolCount: Int, colorCount: Int, maxWidth: CGFloat, maxHeight: CGFloat)
        -> (rect: CGRect, toolBoxes: [CGRect], colorBoxes: [CGRect], rows: Int)? {
        guard toolCount > 0, maxWidth >= item + edgePad * 2 else { return nil }
        let perRow = max(1, Int(((maxWidth - edgePad * 2 + gap) / (item + gap)).rounded(.down)))
        let toolRows = (toolCount + perRow - 1) / perRow
        let rows = toolRows + (colorCount > 0 ? 1 : 0)
        let rowHeight = item + 8                       // 与单行布局的 34pt 同源
        let totalHeight = CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * 2
        guard totalHeight <= maxHeight else { return nil }
        let usedWidth = min(maxWidth, CGFloat(perRow) * (item + gap) - gap + edgePad * 2)
        let rect = CGRect(x: 0, y: 0, width: usedWidth, height: totalHeight)

        var toolBoxes: [CGRect] = []
        for index in 0..<toolCount {
            let row = index / perRow, column = index % perRow
            let x = edgePad + CGFloat(column) * (item + gap)
            // 行从上往下排（视图 y 向上 ⇒ 第一行的 y 更大）
            let y = rect.height - (CGFloat(row) + 1) * rowHeight - CGFloat(row) * 2 + 4
            toolBoxes.append(CGRect(x: x, y: y, width: item, height: item))
        }
        var colorBoxes: [CGRect] = []
        if colorCount > 0 {
            let y = rect.height - CGFloat(rows) * rowHeight - CGFloat(rows - 1) * 2 + (rowHeight - colorDot) / 2
            for index in 0..<colorCount {
                colorBoxes.append(CGRect(x: edgePad + CGFloat(index) * colorStep, y: y, width: colorDot, height: colorDot))
            }
        }
        return (rect, toolBoxes, colorBoxes, rows)
    }

}