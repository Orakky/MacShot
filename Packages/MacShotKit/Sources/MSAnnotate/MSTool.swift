import CoreGraphics
import Foundation

/// 遮罩与贴图再编辑态**共用**这张工具表（11-17 从 `MSOverlay` 下沉到这里，因为 `MSPin`
/// 按依赖方向不许 import `MSOverlay`，而 `UI-004` 要求贴图用"UI-002 同款工具条"）。
/// 字母真源是 `design/keymap.md` §3；`rect` 此前自占了 §2 分给"重复上次区域"的 `R`，已改回 `M`。
/// 键位有一处上下文冲突：`E` 在遮罩里＝橡皮擦，在贴图浏览态＝进入/退出再编辑（§4）。
/// 取"**浏览态 `E` 归贴图，编辑态 `E` 归工具**"，退出编辑另用 `Enter`/`Esc`——已记进 `keymap.md` §4。
public enum MSTool: String, CaseIterable, Sendable {
    case select, rect, ellipse, arrow, polyline, highlighter, pen, blur, badge, eraser, text

    public var letter: String {
        switch self {
        case .select: "V"; case .rect: "M"; case .ellipse: "O"; case .arrow: "A"
        case .polyline: "L"; case .highlighter: "H"; case .pen: "P"; case .blur: "B"
        case .badge: "N"; case .eraser: "E"; case .text: "T"
        }
    }

    public var annotationKind: MSAnnotationKind? {
        switch self {
        case .select: nil
        case .rect: .rect
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .polyline: .polyline
        case .highlighter: .freehand
        case .pen: .freehand
        case .blur: .blur
        case .badge: .badge
        case .eraser: .eraser
        case .text: .text
        }
    }

    /// 单击就完成语义的工具：不进入拖拽草稿（`annotate-model.md` §4）。
    /// 橡皮擦不是"画一个 eraser 元素"——渲染器对 `.eraser` 明确不画任何东西，它是删元素的动作。
    public var isClickAction: Bool { self == .badge || self == .eraser }

    public var isFreehandPen: Bool { self == .pen }
}
