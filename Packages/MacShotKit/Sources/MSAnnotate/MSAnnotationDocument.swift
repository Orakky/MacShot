import CoreGraphics
import Foundation
import MSCore

/// Visual parameters, copied into every element so changing the current style never restyles
/// elements drawn before it (`requirements.md#FR-ANN-003`).
public struct MSAnnotationStyle: Hashable, Sendable, Codable {
    public enum Dash: String, Sendable, Codable { case solid, dash, dot }
    public enum ArrowHead: String, Sendable, Codable { case single, double, triangle }
    public enum BlurKind: String, Sendable, Codable { case pixelate, gaussian }

    public var stroke: MSColorRGBA
    public var fill: MSColorRGBA?
    public var lineWidth: Int
    public var cornerRadius: Int
    public var dash: Dash
    public var arrowHead: ArrowHead
    public var fontSize: Int
    public var bold: Bool
    public var blurKind: BlurKind
    public var blurRadius: Int

    public init(stroke: MSColorRGBA = .rgb(232, 51, 71),
                fill: MSColorRGBA? = nil,
                lineWidth: Int = 3,
                cornerRadius: Int = 0,
                dash: Dash = .solid,
                arrowHead: ArrowHead = .single,
                fontSize: Int = 18,
                bold: Bool = false,
                blurKind: BlurKind = .pixelate,
                blurRadius: Int = 12) {
        self.stroke = stroke; self.fill = fill; self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius; self.dash = dash; self.arrowHead = arrowHead
        self.fontSize = fontSize; self.bold = bold; self.blurKind = blurKind; self.blurRadius = blurRadius
    }

    public static let standard = MSAnnotationStyle()
}

/// Tool families. `Q-03` recommendation = the 9 P0 tools; later kinds are appended only
/// (`ADR-009`: raw values are a permanent contract).
public enum MSAnnotationKind: String, Hashable, Sendable, Codable, CaseIterable {
    case rect, ellipse, arrow, polyline, freehand, text, badge, blur, eraser
    case line, spotlight, crop

    /// Kinds shipped in P0, in toolbar order (`design/screens.md#UI-002`).
    public static let p0Tools: [MSAnnotationKind] = [.rect, .ellipse, .arrow, .polyline, .freehand, .text, .badge, .blur, .eraser]

    /// Whether a drag extends `points` instead of replacing the pair.
    public var takesFreehandPoints: Bool { self == .freehand || self == .polyline }
    public var isTextual: Bool { self == .text || self == .badge }
}

public struct MSAnnotationElement: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var kind: MSAnnotationKind
    /// Canvas pixel space, origin top-left, y growing down (`ADR-013`). Never logical points:
    /// that is what makes the same document render identically at any backing scale.
    public var points: [MSIntPoint]
    public var style: MSAnnotationStyle
    public var z: Int
    public var text: String
    /// Freehand sub-tool: `nil` = highlighter (translucent wide multiply stroke), `"pen"` = opaque pen.
    /// Optional so documents written before the distinction still decode (`ADR-009`).
    public var variant: String?
    /// Freehand strokes may cache a bounds that is cheaper to keep than to re-derive.
    public var boundsOverride: MSIntRect?

    public init(id: UUID = UUID(), kind: MSAnnotationKind, points: [MSIntPoint],
                style: MSAnnotationStyle = .standard, z: Int = 0, text: String = "",
                variant: String? = nil, boundsOverride: MSIntRect? = nil) {
        self.id = id; self.kind = kind; self.points = points; self.style = style
        self.z = z; self.text = text; self.variant = variant; self.boundsOverride = boundsOverride
    }

    public var isPen: Bool { variant == "pen" }
}

/// The annotation layer of one image. Value type, `Sendable`: it crosses actor boundaries by copy,
/// so pins and exports can never alias each other's edits.
public struct MSAnnotationDocument: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let canvasSize: MSIntSize
    public var elements: [MSAnnotationElement]
    public var currentStyle: MSAnnotationStyle
    /// Next auto number for `badge` (`FR-ANN-002`).
    public var badgeCounter: Int

    public init(canvasSize: MSIntSize,
                elements: [MSAnnotationElement] = [],
                currentStyle: MSAnnotationStyle = .standard,
                schemaVersion: Int = MSAnnotationDocument.currentSchemaVersion,
                badgeCounter: Int = 1) {
        self.schemaVersion = schemaVersion
        self.canvasSize = canvasSize
        self.elements = elements
        self.currentStyle = currentStyle
        self.badgeCounter = badgeCounter
    }

    public var isEmpty: Bool { elements.isEmpty }
    public var sortedElements: [MSAnnotationElement] { elements.sorted { $0.z < $1.z } }

    public mutating func append(_ element: MSAnnotationElement) {
        var e = element
        e.z = (elements.map(\.z).max() ?? -1) + 1
        if e.kind == .badge, e.text.isEmpty { e = withBadgeNumber(e) }
        elements.append(e)
    }

    public mutating func replace(_ element: MSAnnotationElement) {
        guard let i = elements.firstIndex(where: { $0.id == element.id }) else { return }
        elements[i] = element
    }

    public mutating func remove(id: UUID) { elements.removeAll { $0.id == id } }
    public func element(id: UUID) -> MSAnnotationElement? { elements.first { $0.id == id } }

    public mutating func raise(id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        let top = elements.map(\.z).max() ?? 0
        if elements[i].z < top { elements[i].z += 1 }
    }

    public mutating func lower(id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        if elements[i].z > 0 { elements[i].z -= 1 }
    }

    private func withBadgeNumber(_ e: MSAnnotationElement) -> MSAnnotationElement {
        var out = e
        out.text = String(badgeCounter)
        return out
    }

    /// Union of element bounds padded by stroke width, clamped to the canvas; nil when empty.
    public var contentBounds: MSIntRect? {
        var result: MSIntRect?
        for e in elements {
            guard let b = MSAnnotationGeometry.bounds(of: e) else { continue }
            let pad = e.style.lineWidth / 2 + 2
            let padded = MSIntRect(x: b.minX - pad, y: b.minY - pad, width: b.width + 2 * pad, height: b.height + 2 * pad)
            result = result.map { $0.union(padded) } ?? padded
        }
        return result?.intersection(MSIntRect(origin: .zero, size: canvasSize))
    }

    /// The next badge value, used by the tool layer before constructing the element.
    public var nextBadgeText: String { String(badgeCounter) }
    public mutating func advanceBadge() { badgeCounter += 1 }
}
