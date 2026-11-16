import Foundation
import MSCore

/// One reversible editing step. Command-based rather than snapshot-based so a document with many
/// elements does not pay a full copy per keystroke (`ADR-011`).
public enum MSAnnotationCommand: Sendable {
    case insert(MSAnnotationElement)
    case remove(MSAnnotationElement)
    case replace(before: MSAnnotationElement, after: MSAnnotationElement)
    case currentStyle(before: MSAnnotationStyle, after: MSAnnotationStyle)
    case badgeCounter(before: Int, after: Int)
    indirect case composite([MSAnnotationCommand])

    public static func compose(_ commands: [MSAnnotationCommand]) -> MSAnnotationCommand? {
        let flat = commands.filter { if case .composite(let inner) = $0 { !inner.isEmpty } else { true } }
        if flat.isEmpty { return nil }
        return flat.count == 1 ? flat[0] : .composite(flat)
    }
}

/// Undo/redo stack scoped to one document instance — a pin keeps its own history across
/// entering and leaving the edit state (`annotate-model.md` §7, `FR-PIN-005`).
public struct MSAnnotationHistory: Sendable {
    public static let depthLimit = 200

    private(set) public var undoStack: [MSAnnotationCommand] = []
    private(set) public var redoStack: [MSAnnotationCommand] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Runs a command and records it. A no-op command (e.g. a click with no movement) is dropped
    /// so it never becomes a phantom undo step.
    @discardableResult
    public mutating func apply(_ command: MSAnnotationCommand, to document: inout MSAnnotationDocument) -> Bool {
        perform(command, on: &document, undo: false)
        undoStack.append(command)
        if undoStack.count > Self.depthLimit { undoStack.removeFirst(undoStack.count - Self.depthLimit) }
        redoStack.removeAll()
        return true
    }

    @discardableResult
    public mutating func undo(_ document: inout MSAnnotationDocument) -> Bool {
        guard let last = undoStack.popLast() else { return false }
        perform(last, on: &document, undo: true)
        redoStack.append(last)
        return true
    }

    @discardableResult
    public mutating func redo(_ document: inout MSAnnotationDocument) -> Bool {
        guard let last = redoStack.popLast() else { return false }
        perform(last, on: &document, undo: false)
        undoStack.append(last)
        return true
    }

    public mutating func removeAll() { undoStack.removeAll(); redoStack.removeAll() }

    private func perform(_ command: MSAnnotationCommand, on doc: inout MSAnnotationDocument, undo: Bool) {
        switch command {
        case .insert(let e):
            if undo { doc.remove(id: e.id) } else { doc.append(e) }
        case .remove(let e):
            if undo { doc.append(e) } else { doc.remove(id: e.id) }
        case .replace(let before, let after):
            doc.replace(undo ? before : after)
        case .currentStyle(let before, let after):
            doc.currentStyle = undo ? before : after
        case .badgeCounter(let before, let after):
            doc.badgeCounter = undo ? before : after
        case .composite(let steps):
            for step in undo ? steps.reversed() : steps { perform(step, on: &doc, undo: undo) }
        }
    }
}

/// Collects the many point updates of a single drag into one undo record: press → 60 updates →
/// release must be one step (`ADR-011`, `FR-ANN-005` judgement "一次拖拽 = 一条撤销记录").
public struct MSDragRecorder: Sendable {
    public let elementBefore: MSAnnotationElement
    public private(set) var latest: MSAnnotationElement

    public init(element: MSAnnotationElement) {
        self.elementBefore = element
        self.latest = element
    }

    public mutating func update(_ element: MSAnnotationElement) { latest = element }

    /// nil when nothing moved, so a stray click adds no undo entry.
    public var command: MSAnnotationCommand? {
        guard latest != elementBefore else { return nil }
        return .replace(before: elementBefore, after: latest)
    }
}
