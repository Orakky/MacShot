import CoreGraphics
import Foundation
import MSCore

/// `UI-008` 放大镜的**纯模型**：几何、镜像、读数串。绘制住在 `MSOverlayView`，
/// 因为这里必须能被 `swift test` 覆盖（`ADR-012`），而画要碰 `NSGraphicsContext`。
///
/// 规格逐条来自 `screens.md#UI-008`：17×17 像素近邻放大到 170pt、中心像素描 accent、
/// 位置在指针右下 20pt、贴边镜像、不覆盖选区把手。
public enum MSLoupeModel {
    public static let pixelCount = 17
    public static let zoom = 10
    public static let boxSide: CGFloat = CGFloat(pixelCount) * CGFloat(zoom)     // 170pt
    public static let readoutHeight: CGFloat = 26
    public static let offset: CGFloat = 20

    /// 半径：中心左右各 8 像素 ⇒ 17。
    public static var radius: Int { pixelCount / 2 }

    /// 只有两档：`FR-CAP-016` 与 `keymap.md` 写的就是 `⇧C` 切 Hex/RGB，不自作主张加第三档。
    public enum Format: Int, CaseIterable, Sendable {
        case hex, rgb
        public var next: Format { Format.allCases[((rawValue + 1) % Format.allCases.count)] }
    }

    /// 放大镜外框（含读数条）。视图坐标 y 向上。
    ///
    /// 顺序按 `UI-008`：先指针**右下 20pt**，被选区把手压住就换象限（左下 → 右上 → 左上），
    /// 而不是把框顶开一大段——放大镜要贴着指针才有用，飘走了就看不见取的是哪个像素。
    /// 四个象限都不行才退回"夹在屏内"，宁可重叠也不出屏。
    public static func rect(anchor: CGPoint, bounds: CGRect, handleRects: [CGRect] = []) -> CGRect {
        let total = CGSize(width: boxSide + 2, height: boxSide + readoutHeight + 2)
        let candidates = [
            CGPoint(x: anchor.x + offset, y: anchor.y - offset - total.height),        // 右下（默认）
            CGPoint(x: anchor.x - offset - total.width, y: anchor.y - offset - total.height),  // 左下
            CGPoint(x: anchor.x + offset, y: anchor.y + offset),                        // 右上
            CGPoint(x: anchor.x - offset - total.width, y: anchor.y + offset),          // 左上
        ]
        for origin in candidates {
            let box = CGRect(origin: origin, size: total)
            if bounds.contains(box) && !handleRects.contains(where: { $0.intersects(box) }) { return box }
        }
        // 都失败：夹回屏内（可能与把手重叠，这是诚实的边界，而不是画到看不见的地方）。
        var origin = candidates[0]
        origin.x = min(max(origin.x, bounds.minX + 2), bounds.maxX - total.width - 2)
        origin.y = min(max(origin.y, bounds.minY + 2), bounds.maxY - total.height - 2)
        return CGRect(origin: origin, size: total)
    }

    /// 网格区（放大镜里"像素"真正占的那块）。绘制与中心格**必须共用这个函数**：
    /// 两边各算各的，近邻图就会被拉成非整数倍，像素糊掉，取色就不准（实测栽过一次）。
    public static func gridRect(in box: CGRect) -> CGRect {
        CGRect(x: box.minX + 1, y: box.minY + readoutHeight + 1,
               width: box.width - 2, height: boxSide)
    }

    /// 中心像素在**视图**里的方格位置（画 accent 框与量墨都用它）。
    public static func centerCell(in box: CGRect) -> CGRect {
        let grid = gridRect(in: box)
        let side = grid.width / CGFloat(pixelCount)
        return CGRect(x: grid.minX + side * CGFloat(radius),
                      y: grid.minY + side * CGFloat(radius),
                      width: side, height: side)
    }

    /// 读数串：色值 + 像素坐标。格式由 `⇧C` 循环（hex → rgb → hsl）。
    public static func readout(color: MSColorRGBA?, pixel: MSIntPoint, format: Format) -> String {
        let value: String
        switch format {
        case .hex: value = color?.hex() ?? "—"
        case .rgb: value = color?.rgbDescription ?? "—"
        }
        return "\(value)  X:\(pixel.x) Y:\(pixel.y)"
    }

    /// `C` 复制的就是读数条上那个色值（不是整串：坐标复制过去没意义）。
    public static func copyString(color: MSColorRGBA?, format: Format) -> String {
        switch format {
        case .hex: return color?.hex() ?? ""
        case .rgb: return color?.rgbDescription ?? ""
        }
    }

    /// 指针视图点 → 冻结帧像素点。冻结帧是整屏，所以换算是"视图点 / 视图高"翻 y，再乘 scale。
    /// 显式写出来而不是"顺手换算"（`ADR-013`）：方向错一个，取色就永远偏半屏。
    public static func pixel(view point: CGPoint, viewHeight: CGFloat, imageSize: MSIntSize, scale: CGFloat) -> MSIntPoint {
        let x = Int((point.x * scale).rounded(.down))
        let yFromTop = Int(((viewHeight - point.y) * scale).rounded(.down))
        return MSIntPoint(x: min(max(0, x), max(0, imageSize.width - 1)),
                          y: min(max(0, yFromTop), max(0, imageSize.height - 1)))
    }
}
