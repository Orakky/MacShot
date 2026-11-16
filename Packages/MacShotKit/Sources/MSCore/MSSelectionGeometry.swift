import CoreGraphics
import Foundation

/// Interactive geometry for the capture overlay: which part of a selection a pointer is on,
/// and how the selection reacts to a drag. Pure math so it can be tested without a window.
public enum MSSelectionGeometry {

    public static let minimumSize: CGFloat = 4

    public enum Handle: String, CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, body, none

        public var isResizing: Bool { self != .body && self != .none }
    }

    /// `hitTolerance` is in logical points; it also grows with the display scale so the grab area
    /// stays about the same physical size on 1x and 2x screens.
    public static func handle(at point: CGPoint, of rect: CGRect, hitTolerance: CGFloat = 6) -> Handle {
        let t = hitTolerance
        let insideBody = rect.insetBy(dx: t, dy: t).contains(point)
        let nearEdge = rect.insetBy(dx: -t, dy: -t).contains(point)
        if nearEdge == false { return .none }
        if insideBody {
            // A corner wins over an edge, and an edge wins over the body.
            if isCorner(point, of: rect, t: t) { return cornerHandle(point, of: rect) }
            if isEdge(point, of: rect, t: t) { return edgeHandle(point, of: rect) }
            return .body
        }
        return isCorner(point, of: rect, t: t) ? cornerHandle(point, of: rect) : edgeHandle(point, of: rect)
    }

    private static func isCorner(_ p: CGPoint, of r: CGRect, t: CGFloat) -> Bool {
        for c in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                  CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            if abs(p.x - c.x) <= t && abs(p.y - c.y) <= t { return true }
        }
        return false
    }

    private static func isEdge(_ p: CGPoint, of r: CGRect, t: CGFloat) -> Bool {
        near(p.x, r.minX, t) || near(p.x, r.maxX, t) || near(p.y, r.minY, t) || near(p.y, r.maxY, t)
    }

    private static func near(_ v: CGFloat, _ target: CGFloat, _ t: CGFloat) -> Bool { abs(v - target) <= t }

    private static func cornerHandle(_ p: CGPoint, of r: CGRect) -> Handle {
        let left = p.x <= r.midX
        let top = p.y >= r.midY // AppKit y grows up
        if left && top { return .topLeft }
        if !left && top { return .topRight }
        if left && !top { return .bottomLeft }
        return .bottomRight
    }

    private static func edgeHandle(_ p: CGPoint, of r: CGRect) -> Handle {
        let horizontal = min(abs(p.x - r.minX), abs(p.x - r.maxX))
        let vertical = min(abs(p.y - r.minY), abs(p.y - r.maxY))
        if vertical <= horizontal { return abs(p.y - r.maxY) <= abs(p.y - r.minY) ? .top : .bottom }
        return abs(p.x - r.minX) <= abs(p.x - r.maxX) ? .left : .right
    }

    /// Drag `handle` by `translation` (AppKit space, y up) and return the new rect.
    /// The result is always normalized (no negative width/height): dragging a corner past the
    /// opposite corner flips the selection instead of corrupting it.
    public static func resized(by translation: CGSize, handle: Handle, from rect: CGRect,
                               minimumSize: CGFloat = minimumSize,
                               clampTo bounds: CGRect? = nil,
                               lockedAspect: CGFloat? = nil) -> CGRect {
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        switch handle {
        case .left: left += translation.width
        case .right: right += translation.width
        case .top: top += translation.height
        case .bottom: bottom += translation.height
        case .topLeft: left += translation.width; top += translation.height
        case .topRight: right += translation.width; top += translation.height
        case .bottomLeft: left += translation.width; bottom += translation.height
        case .bottomRight: right += translation.width; bottom += translation.height
        case .body, .none: break
        }
        var out = CGRect(x: min(left, right), y: min(bottom, top),
                         width: Swift.max(minimumSize, abs(right - left)),
                         height: Swift.max(minimumSize, abs(top - bottom)))
        if let aspect = lockedAspect {
            out = applyAspect(aspect, to: out, anchoredAt: fixedCorner(for: handle, of: rect))
        }
        if let bounds { out = clamp(out, to: bounds, minimumSize: minimumSize) }
        return out
    }

    public static func moved(by translation: CGSize, rect: CGRect, clampTo bounds: CGRect? = nil) -> CGRect {
        var out = rect.offsetBy(dx: translation.width, dy: translation.height)
        if let bounds {
            out.origin.x = Swift.min(Swift.max(out.minX, bounds.minX), Swift.max(bounds.minX, bounds.maxX - out.width))
            out.origin.y = Swift.min(Swift.max(out.minY, bounds.minY), Swift.max(bounds.minY, bounds.maxY - out.height))
        }
        return out
    }

    public static func applyAspect(_ aspect: CGFloat, to rect: CGRect, anchoredAt anchor: CGPoint) -> CGRect {
        var width = rect.width, height = rect.height
        if width / height > aspect { height = width / aspect } else { width = height * aspect }
        let x = anchor.x <= rect.midX ? rect.minX : rect.maxX - width
        let y = anchor.y <= rect.midY ? rect.minY : rect.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func fixedCorner(for handle: Handle, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.maxX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.minX, y: rect.maxY)
        default: return CGPoint(x: rect.minX, y: rect.minY)
        }
    }

    public static func clamp(_ rect: CGRect, to bounds: CGRect, minimumSize: CGFloat = minimumSize) -> CGRect {
        let w = Swift.min(rect.width, bounds.width)
        let h = Swift.min(rect.height, bounds.height)
        let x = Swift.min(Swift.max(rect.minX, bounds.minX), bounds.maxX - w)
        let y = Swift.min(Swift.max(rect.minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: Swift.max(minimumSize, w), height: Swift.max(minimumSize, h))
    }

    /// Snapping candidates while dragging: edges, centres and corners of the desktop,
    /// other displays, pinned windows and the previous selection.
    public static func snapTargets(from rects: [CGRect]) -> (x: [CGFloat], y: [CGFloat]) {
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for r in rects {
            xs.append(contentsOf: [r.minX, r.midX, r.maxX])
            ys.append(contentsOf: [r.minY, r.midY, r.maxY])
        }
        return (Array(Set(xs)).sorted(), Array(Set(ys)).sorted())
    }

    /// Returns the adjusted coordinate when `value` is within `tolerance` of a target.
    public static func snapped(_ value: CGFloat, to targets: [CGFloat], tolerance: CGFloat) -> CGFloat? {
        var best: (delta: CGFloat, target: CGFloat)?
        for t in targets {
            let d = abs(value - t)
            if d <= tolerance, d < (best?.delta ?? .infinity) { best = (d, t) }
        }
        return best?.target
    }
}
