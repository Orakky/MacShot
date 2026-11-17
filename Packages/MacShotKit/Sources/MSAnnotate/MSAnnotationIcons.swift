import CoreGraphics
import Foundation

/// 工具图标的**事实表**（`design-system.md` §5）：哪个工具用哪个符号名、哪格自绘。
///
/// 这里刻意不 import AppKit——`check-deps` 与 `charter.md` §4 要求标注模块不持窗口/AppKit，
/// 而 SF Symbols 只能经 `NSImage` 取。装载与着色因此住在两个 UI 模块里各一份
/// （`MSOverlayIcons` / `MSPinIcons`），共同点只有这张表；收拢成共享 UI-kit 模块要一条 ADR（`B-031`）。
/// 折线箭头没有符号（`path.forward` / `curve` 实测都不存在），按 §5 自绘，画法也在这里，纯 CGContext。
public enum MSAnnotationIconTable {
    /// 图标边长，真源是 `UI-002` 的"图标 16pt"。
    public static let side: CGFloat = 16

    /// 工具 → SF Symbol 名；`nil` = 没有符号，走 `drawPolylineArrow`。
    public static func symbolName(for tool: MSTool) -> String? {
        switch tool {
        case .select: "cursorarrow"
        case .rect: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .polyline: nil
        case .highlighter: "highlighter"
        case .pen: "pencil.line"
        case .blur: "circle.grid.2x2"
        case .badge: "number"
        case .eraser: "eraser"
        case .text: "character.cursor.ibeam"      // 本机渲染成「文」+ 光标，中文界面正好
        }
    }

    /// 折线箭头：两段折线 + 箭头帽，按 12 格比例缩放。纯路径，谁都能画。
    public static func polylinePath(in rect: CGRect) -> CGPath {
        let s = rect.width / 12
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX + 1.6 * s, y: rect.minY + 2.6 * s))
        p.addLine(to: CGPoint(x: rect.minX + 5.4 * s, y: rect.minY + 8.2 * s))
        p.addLine(to: CGPoint(x: rect.minX + 7.6 * s, y: rect.minY + 5.6 * s))
        p.move(to: CGPoint(x: rect.minX + 10.4 * s, y: rect.minY + 9.4 * s))
        p.addLine(to: CGPoint(x: rect.minX + 7.6 * s, y: rect.minY + 5.6 * s))
        p.addLine(to: CGPoint(x: rect.minX + 5.2 * s, y: rect.minY + 6.6 * s))
        return p
    }
}
