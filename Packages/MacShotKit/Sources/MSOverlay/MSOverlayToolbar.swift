import CoreGraphics
import Foundation
import MSAnnotate

/// 工具条布局（规格见 `design/screens.md#UI-002`）。
///
/// **绘制与命中都从这里取矩形**：此前 `drawToolbar` 和 `hitToolbar` 各算一遍 x，
/// 还各有一套截断规则——那就是 11-16 遮罩 ✕「画在左下、点在左上」的同一个形状。
///
/// 宽度不够时的取舍顺序是定死的：先收掉键位提示文字（它和屏底提示条重复），
/// 再考虑工具；位置永远钳制在屏内，所以贴边的选区不会把工具推出屏幕。
public enum MSOverlayToolbar {
    /// 度量只有一个家：`MSAnnotationToolbar`（贴图再编辑态用同一条工具条，而 `MSPin`
    /// 不许 import `MSOverlay`）。这里只保留**遮罩特有的摆放**：贴着选区、钳在屏内。
    public static var item: CGFloat { MSAnnotationToolbar.item }
    public static var gap: CGFloat { MSAnnotationToolbar.gap }
    public static var height: CGFloat { MSAnnotationToolbar.height }
    public static var edgePad: CGFloat { MSAnnotationToolbar.edgePad }
    public static var colorGroupGap: CGFloat { MSAnnotationToolbar.colorGroupGap }
    public static var colorDot: CGFloat { MSAnnotationToolbar.colorDot }
    public static var colorStep: CGFloat { MSAnnotationToolbar.colorStep }
    public static var actionWidth: CGFloat { MSAnnotationToolbar.actionWidth }
    public static var screenMargin: CGFloat { MSAnnotationToolbar.screenMargin }
    public static var selectionGap: CGFloat { MSAnnotationToolbar.selectionGap }

    public struct Layout {
        public let rect: CGRect
        public let toolBoxes: [(MSTool, CGRect)]
        public let colorBoxes: [(String, CGRect)]
        public let showsActions: Bool
    }

    public static func naturalWidth(toolCount: Int, colorCount: Int, showsActions: Bool) -> CGFloat {
        MSAnnotationToolbar.naturalWidth(itemCount: toolCount, colorCount: colorCount, showsActions: showsActions)
    }

    public static func layout(selection: CGRect, bounds: CGRect, tools: [MSTool], colors: [String]) -> Layout {
        let showActions = MSAnnotationToolbar.showsActions(widthAvailable: bounds.width,
                                                          itemCount: tools.count, colorCount: colors.count)
        let contentWidth = naturalWidth(toolCount: tools.count, colorCount: colors.count, showsActions: showActions)
        let barWidth = min(contentWidth, max(0, bounds.width - screenMargin * 2))
        // x：贴着选区左上，但整条必须留在屏内
        let x = min(max(selection.minX, bounds.minX + screenMargin),
                    max(bounds.minX + screenMargin, bounds.maxX - screenMargin - barWidth))
        // y：优先放选区上方；放不下就翻到下方
        let above = selection.minY - height - selectionGap
        let y = above >= bounds.minY + screenMargin ? above : min(selection.maxY + selectionGap,
                                                                  bounds.maxY - screenMargin - height)
        let rect = CGRect(x: x, y: y, width: barWidth, height: height)
        let boxes = MSAnnotationToolbar.boxes(rect: rect, itemCount: tools.count, colorCount: colors.count)
        return Layout(rect: rect,
                      toolBoxes: Array(zip(tools, boxes.items)),
                      colorBoxes: Array(zip(colors, boxes.colors)),
                      showsActions: showActions)
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
