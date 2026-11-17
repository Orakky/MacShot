import Foundation

/// Thin seams over the outside world so capability modules stay testable without a display,
/// a pasteboard or a filesystem (`overview.md` §7). AppKit-backed conformance lives in `App/`.

public protocol MSClock: Sendable {
    func now() -> Date
}

public struct SystemClock: MSClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedClock: MSClock {
    private let date: Date
    public init(_ date: Date) { self.date = date }
    public func now() -> Date { date }
}

/// Writing an image to the system pasteboard. The PNG payload is pre-encoded off the main actor
/// and the implementation performs one atomic write (`ADR-014`).
///
/// 只有一个载荷是有意的：`Q-04` 裁定剪贴板只写 PNG。以前"猜"要双写 TIFF，
/// 结果 `MSPNGItem` 得替 `.tiff` 现算一份表示，两边不一致就成了粘贴事故的源头。
public protocol MSPasteboardWriting: Sendable {
    var changeCount: Int { get }
    @discardableResult func writeImage(png: Data) -> Bool
    /// 纯文本写入（放大镜取色 `C`，`FR-CAP-016`）。同样一次 `clearContents` + 一次写。
    @discardableResult func writeText(_ text: String) -> Bool
}

public protocol MSFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
}

public enum MSFileError: Error, Equatable, Sendable {
    case directoryUnusable(path: String)
    case writeFailed(path: String, reason: String)
}

public struct DiskFileWriter: MSFileWriting {
    public init() {}
    public func write(_ data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw MSFileError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }
    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
