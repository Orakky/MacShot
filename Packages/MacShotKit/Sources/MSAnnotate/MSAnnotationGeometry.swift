import CoreGraphics
import Foundation
import MSCore

/// Geometry shared by hit-testing, selection handles and the renderer. Everything works in
/// canvas pixel space (y down); callers convert mouse coordinates before entering.
public enum MSAnnotationGeometry {

    /// Padding that keeps a stroked element's handles reachable on a 1px line.
    public static func hitTolerance(for element: MSAnnotationElement) -> Int {
        max(4, element.style.lineWidth + 2)
    }

    public static func bounds(of element: MSAnnotationElement) -> MSIntRect? {
        if let override = element.boundsOverride { return override }
        switch element.kind {
        case .badge:
            guard let c = element.points.first else { return nil }
            let r = badgeRadius(for: element)
            return MSIntRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .text:
            guard let o = element.points.first else { return nil }
            let lines = max(1, element.text.components(separatedBy: "\n").count)
            let longest = element.text.components(separatedBy: "\n").map { $0.count }.max() ?? 1
            let w = Int((Double(max(1, longest)) * Double(element.style.fontSize) * 0.62).rounded(.up))
            let h = Int((Double(lines) * Double(element.style.fontSize) * 1.32).rounded(.up))
            return MSIntRect(x: o.x, y: o.y, width: max(8, w), height: max(8, h))
        default:
            guard let first = element.points.first else { return nil }
            var rect = MSIntRect(origin: first, size: .zero)
            for p in element.points.dropFirst() {
                rect = rect.union(MSIntRect(origin: p, size: .zero))
            }
            return rect
        }
    }

    /// Radius grows with digit count so 1→99 keeps the same optical size (`annotate-model.md` §5.3).
    public static func badgeRadius(for element: MSAnnotationElement) -> Int {
        let base = Int((Double(element.style.fontSize) * 0.72).rounded(.up))
        let digits = max(1, element.text.count)
        return base + max(0, digits - 1) * max(2, element.style.fontSize * 2 / 13)
    }

    public static func textLineHeight(for element: MSAnnotationElement) -> Int {
        Int((Double(element.style.fontSize) * 1.32).rounded(.up))
    }

    public static func hitTest(_ point: CGPoint, element: MSAnnotationElement, extraTolerance: Int = 0) -> Bool {
        let tol = Double(hitTolerance(for: element) + extraTolerance)
        switch element.kind {
        case .line, .arrow, .polyline, .freehand:
            return distanceToPath(point, element: element) <= tol
        case .rect, .ellipse, .blur, .spotlight, .crop, .eraser:
            guard let b = bounds(of: element) else { return false }
            let outer = b.cgRect.insetBy(dx: -tol, dy: -tol)
            guard outer.contains(point) else { return false }
            if element.style.fill != nil, element.kind != .blur, element.kind != .eraser { return true }
            let inner = b.cgRect.insetBy(dx: tol + Double(element.style.lineWidth), dy: tol + Double(element.style.lineWidth))
            return !inner.contains(point)
        case .text, .badge:
            guard let b = bounds(of: element) else { return false }
            return b.cgRect.insetBy(dx: -tol, dy: -tol).contains(point)
        }
    }

    public static func distanceToPath(_ p: CGPoint, element: MSAnnotationElement) -> Double {
        let pts = element.points.map { CGPoint(x: $0.x, y: $0.y) }
        guard pts.count > 1 else { return pts.first.map { hypot(p.x - $0.x, p.y - $0.y) } ?? .infinity }
        var best = Double.infinity
        for i in 0..<(pts.count - 1) { best = min(best, distance(p, a: pts[i], b: pts[i + 1])) }
        return best
    }

    private static func distance(_ p: CGPoint, a: CGPoint, b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// 8 handles of an element in canvas pixel space, ordered nw,n,ne,e,se,s,sw,w.
    public static func handles(of element: MSAnnotationElement) -> [CGPoint] {
        guard let b = bounds(of: element) else { return [] }
        let r = b.cgRect
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    public static func translated(_ element: MSAnnotationElement, by delta: CGSize) -> MSAnnotationElement {
        var out = element
        let dx = Int(delta.width.rounded()), dy = Int(delta.height.rounded())
        out.points = element.points.map { MSIntPoint(x: $0.x + dx, y: $0.y + dy) }
        if let b = element.boundsOverride {
            out.boundsOverride = MSIntRect(x: b.minX + dx, y: b.minY + dy, width: b.width, height: b.height)
        }
        return out
    }

    /// Uniform rescale about an anchor. Used by future "resize selection keeps annotations" work
    /// (`FR-ANN-012`) — the P0 behaviour is to clear instead (`Q-11`).
    public static func scaled(_ element: MSAnnotationElement, factor: Double, about anchor: MSIntPoint) -> MSAnnotationElement {
        var out = element
        out.points = element.points.map {
            MSIntPoint(x: Int((Double($0.x - anchor.x) * factor + Double(anchor.x)).rounded()),
                       y: Int((Double($0.y - anchor.y) * factor + Double(anchor.y)).rounded()))
        }
        return out
    }

    /// Canvas-space rectangle for the two-point kinds, normalized (no negative size).
    public static func normalizedRect(from a: MSIntPoint, to b: MSIntPoint) -> MSIntRect {
        MSIntRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
