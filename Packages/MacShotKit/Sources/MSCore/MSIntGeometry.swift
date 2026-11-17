import CoreGraphics
import Foundation

/// Integer pixel geometry. Every pixel-space value in MacShot uses these types so that
/// fractional coordinates cannot silently reappear between capture, annotation and export.
public struct MSIntPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static let zero = MSIntPoint(x: 0, y: 0)

    /// 画布像素（选区本地，原点左上、y 向下）→ 视图点（y 向上），即 `MSIntRect(flippedLogical:scale:)`
    /// 的反向。文字 field editor 要按画布锚点摆到屏幕上，必须有显式函数而不是就地再写一遍乘除
    /// （`ADR-013` §6：新换算先写单测）。
    public func viewPoint(in selection: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: selection.minX + CGFloat(x) / scale,
                y: selection.maxY - CGFloat(y) / scale)
    }

    /// 正向：视图点（y 向上）→ 画布像素（选区本地，y 向下）。
    /// 两个方向必须放在一起、互为逆运算，否则就会出现"某处又翻了一遍 y"的坐标 bug
    /// （2026-11-16 实拍抓到的 ✕ 画在左下就是这种形状）。
    public static func canvasPoint(of view: CGPoint, in selection: CGRect, scale: CGFloat) -> MSIntPoint {
        MSIntPoint(x: Int(((view.x - selection.minX) * scale).rounded()),
                   y: Int(((selection.maxY - view.y) * scale).rounded()))
    }
}

public struct MSIntSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public static let zero = MSIntSize(width: 0, height: 0)

    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var aspectRatio: CGFloat { height == 0 ? 1 : CGFloat(width) / CGFloat(height) }
}

/// A rectangle on the physical pixel grid: origin top-left, y growing down.
public struct MSIntRect: Hashable, Sendable, Codable {
    public var origin: MSIntPoint
    public var size: MSIntSize

    public init(origin: MSIntPoint, size: MSIntSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: MSIntPoint(x: x, y: y), size: MSIntSize(width: width, height: height))
    }

    public var minX: Int { origin.x }
    public var midX: Int { origin.x + size.width / 2 }
    public var midY: Int { origin.y + size.height / 2 }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public var width: Int { size.width }
    public var height: Int { size.height }
    public var isEmpty: Bool { size.isEmpty }
    public var cgRect: CGRect { CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height) }

    /// Both edges snap to the pixel grid independently, so width == round(maxX*scale) - minX*scale
    /// rather than round(width*scale) — the difference is what stops a 1px bleed on 1.799x displays.
    public init(flippedLogical rect: CGRect, scale: CGFloat) {
        let minX = Int((rect.minX * scale).rounded())
        let minY = Int((rect.minY * scale).rounded())
        let maxX = Int((rect.maxX * scale).rounded())
        let maxY = Int((rect.maxY * scale).rounded())
        self.init(x: minX, y: minY, width: Swift.max(0, maxX - minX), height: Swift.max(0, maxY - minY))
    }

    public func insetBy(_ dx: Int, _ dy: Int) -> MSIntRect {
        MSIntRect(x: minX + dx, y: minY + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func intersection(_ other: MSIntRect) -> MSIntRect? {
        let x = Swift.max(minX, other.minX)
        let y = Swift.max(minY, other.minY)
        let maxX = Swift.min(self.maxX, other.maxX)
        let maxY = Swift.min(self.maxY, other.maxY)
        guard maxX > x, maxY > y else { return nil }
        return MSIntRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    public func union(_ other: MSIntRect) -> MSIntRect {
        let x = Swift.min(minX, other.minX)
        let y = Swift.min(minY, other.minY)
        let maxX = Swift.max(self.maxX, other.maxX)
        let maxY = Swift.max(self.maxY, other.maxY)
        return MSIntRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    public func contains(_ p: MSIntPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}
