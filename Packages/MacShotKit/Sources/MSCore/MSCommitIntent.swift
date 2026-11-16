import Foundation

/// What a commit does with the result. Defined in `MSCore` because the overlay produces it, the
/// session routes it and the exporter acts on it (`export-clipboard.md` §5).
public enum MSCommitIntent: String, Sendable, CaseIterable, Codable {
    case copy
    case pin
    case savePanel
    case quickSave
    case cancel
}

public enum MSErrors: Error, Equatable, Sendable {
    case permissionMissing
    case noSelection
    case captureFailed(String)
    case exportFailed(String)
    case clipboardUnowned
}

/// Image container the user can pick for saved files. Lives in `MSCore` because settings stores it
/// and export acts on it (`modules.md` §12 dependency rules).
public enum MSImageFormat: String, Sendable, Codable, CaseIterable {
    case png, jpeg
    public var fileExtension: String { self == .png ? "png" : "jpg" }
}
