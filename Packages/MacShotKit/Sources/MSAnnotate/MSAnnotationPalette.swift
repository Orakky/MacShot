import Foundation

/// 工具条色板（真源 `design/design-system.md` §2.2 的 8 格，顺序固定）。
/// 遮罩与贴图再编辑态共用同一份——此前 6 个十六进制串硬编码在 `MSOverlayView` 里，
/// 贴图侧要画同一条工具条就只能再抄一遍，那就是第二个家。
public enum MSAnnotationPalette {
    /// 8 格内容色，顺序即工具条顺序。
    public static let swatches = ["#E83347", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#AF52DE", "#000000", "#FFFFFF"]
    /// 工具条上直接露出的前 6 格（黑/白与"自定义取色"入口留给样式面板，属 P1）。
    public static let toolbar = Array(swatches.prefix(6))
}
