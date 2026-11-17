import CoreGraphics
import Foundation

/// 工具条布局（规格见 `design/screens.md#UI-002`）。
///
/// **绘制与命中都从这里取矩形**：此前 `drawToolbar` 和 `hitToolbar` 各算一遍 x，
/// 还各有一套截断规则——那就是 11-16 遮罩 ✕「画在左下、点在左上」的同一个形状。
///
/// 宽度不够时的取舍顺序是定死的：先收掉键位提示文字（它和屏底提示条重复），
/// 再考虑工具；位置永远钳制在屏内，所以贴边的选区不会把工具推出屏幕。
public enum MSOverlayToolbar {
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

    public struct Layout {
        public let rect: CGRect
        public let toolBoxes: [(MSTool, CGRect)]
        public let colorBoxes: [(String, CGRect)]
        public let showsActions: Bool
    }

    public static func naturalWidth(toolCount: Int, colorCount: Int, showsActions: Bool) -> CGFloat {
        let tools = CGFloat(toolCount) * (item + gap)
        let colors = CGFloat(colorCount) * colorStep
        return edgePad * 2 + tools + colorGroupGap + colors + (showsActions ? actionWidth : 0)
    }

    public static func layout(selection: CGRect, bounds: CGRect, tools: [MSTool], colors: [String]) -> Layout {
        let fitsEverything = naturalWidth(toolCount: tools.count, colorCount: colors.count, showsActions: true)
        let usable = max(0, bounds.width - screenMargin * 2)
        let showActions = fitsEverything <= usable
        let contentWidth = naturalWidth(toolCount: tools.count, colorCount: colors.count, showsActions: showActions)
        let barWidth = min(contentWidth, usable)
        // x：贴着选区左上，但整条必须留在屏内
        let x = min(max(selection.minX, bounds.minX + screenMargin),
                    max(bounds.minX + screenMargin, bounds.maxX - screenMargin - barWidth))
        // y：优先放选区上方；放不下就翻到下方
        let above = selection.minY - height - selectionGap
        let y = above >= bounds.minY + screenMargin ? above : min(selection.maxY + selectionGap,
                                                                  bounds.maxY - screenMargin - height)
        let rect = CGRect(x: x, y: y, width: barWidth, height: height)

        var toolBoxes: [(MSTool, CGRect)] = []
        var cx = rect.minX + edgePad
        for t in tools {
            let box = CGRect(x: cx, y: rect.minY + 4, width: item, height: item)
            toolBoxes.append((t, box))
            cx += item + gap
        }
        var colorBoxes: [(String, CGRect)] = []
        cx += colorGroupGap - gap
        for hex in colors {
            colorBoxes.append((hex, CGRect(x: cx, y: rect.midY - colorDot / 2, width: colorDot, height: colorDot)))
            cx += colorStep
        }
        return Layout(rect: rect, toolBoxes: toolBoxes, colorBoxes: colorBoxes, showsActions: showActions)
    }

    /// 尺寸读数药丸的落位（`screens.md#UI-001` 第 5 行）：优先选区**右下外侧** 8pt；
    /// 外侧被工具条占住、或越出屏幕 ⇒ 翻到选区**内侧**。实测过一次遮挡：药丸画在工具条底下，
    /// 于是"常显的尺寸读数"等于没有（`FR-CAP-002`）。
    public static func readoutOrigin(selection: CGRect, bounds: CGRect, readoutSize: CGSize,
                                     toolbar: CGRect?) -> CGPoint {
        let outside = CGPoint(x: min(max(selection.maxX - readoutSize.width, bounds.minX + screenMargin),
                                     bounds.maxX - screenMargin - readoutSize.width),
                              y: selection.minY - readoutSize.height - 8)
        let outsideRect = CGRect(origin: outside, size: readoutSize)
        let blocked = (outside.y < bounds.minY + screenMargin)
            || (toolbar.map { !$0.intersection(outsideRect).isEmpty } ?? false)
        if !blocked { return outside }
        return CGPoint(x: selection.maxX - readoutSize.width - 8,
                       y: selection.minY + 8)
    }
}
