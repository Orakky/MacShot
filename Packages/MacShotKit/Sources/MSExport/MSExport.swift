/// `${var}` expansion for file names (`FR-EXP-003`). The variable list is the one in
/// `docs/architecture/export-clipboard.md` §4 — extend there first.
public struct MSNamingTemplate: Sendable {
    public var pattern: String
    public init(_ pattern: String) { self.pattern = pattern }

    public struct Context: Sendable {
        public var date: Date
        public var pixelSize: MSIntSize
        public var scale: Int
        public var displayName: String
        public init(date: Date = Date(), pixelSize: MSIntSize = .zero, scale: Int = 1, displayName: String = "") {
            self.date = date; self.pixelSize = pixelSize; self.scale = scale; self.displayName = displayName
        }
    }

    public func expand(_ c: Context, index: Int = 1) -> String {
        let cal = Calendar.current
        let parts: [String: String] = [
            "{yyyy}": String(format: "%04d", cal.component(.year, from: c.date)),
            "{MM}": String(format: "%02d", cal.component(.month, from: c.date)),
            "{dd}": String(format: "%02d", cal.component(.day, from: c.date)),
            "{HH}": String(format: "%02d", cal.component(.hour, from: c.date)),
            "{mm}": String(format: "%02d", cal.component(.minute, from: c.date)),
            "{ss}": String(format: "%02d", cal.component(.second, from: c.date)),
            "{width}": String(c.pixelSize.width),
            "{height}": String(c.pixelSize.height),
            "{scale}": "@\(c.scale)x",
            "{display}": c.displayName.replacingOccurrences(of: " ", with: "-"),
            "{index}": String(format: "%03d", index),
            "{tool}": "MacShot",
        ]
        var out = pattern
        for (k, v) in parts { out = out.replacingOccurrences(of: k, with: v) }
        return out.components(separatedBy: CharacterSet(charactersIn: "\\/:")).filter { !$0.isEmpty }.joined(separator: "-")
    }
}

import CoreGraphics
import Foundation
import ImageIO
import MSCore
import MSAnnotate
import UniformTypeIdentifiers

/// One-way bake: document → pixels. Exports never carry the document (`charter.md` §1.1 对策 3).
public struct MSBitmapBaker {
    private let renderer: any MSAnnotationRendering
    public init(renderer: any MSAnnotationRendering = MSAnnotationRenderer()) { self.renderer = renderer }

    public func bake(_ document: MSAnnotationDocument, source: CGImage?) -> CGImage? {
        renderer.render(document, source: source, intent: .export)
    }
}

public enum MSImageEncoder {
    /// DPI is `72 × backing scale` so the receiving app sizes the image by its logical dimensions
    /// (`FR-EXP-004`). `kCGImagePropertyDPIWidth/Height` is what ImageIO honours for both PNG and
    /// TIFF, and it is read back by the test — no hand-written pHYs chunk.
    public static func dpi(scale: Int) -> Int { max(72, 72 * max(1, scale)) }

    public static func png(_ image: CGImage, scale: Int) -> Data? {
        encode(image, type: UTType.png.identifier as CFString, scale: scale, quality: nil)
    }

    public static func tiff(_ image: CGImage, scale: Int) -> Data? {
        encode(image, type: UTType.tiff.identifier as CFString, scale: scale, quality: nil)
    }

    public static func jpeg(_ image: CGImage, scale: Int, quality: Double) -> Data? {
        encode(image, type: UTType.jpeg.identifier as CFString, scale: scale, quality: quality)
    }

    private static func encode(_ image: CGImage, type: CFString, scale: Int, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        let d = CGFloat(dpi(scale: scale))
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: d, kCGImagePropertyDPIHeight: d]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Read-back used by `V-005`: the file must report the DPI we asked for.
    public static func reportedDPI(of data: Data) -> Int? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let dpi = props[kCGImagePropertyDPIWidth] as? CGFloat else { return nil }
        return Int(dpi.rounded())
    }
}

public enum MSImageDecoder {
    /// Used by the losslessness test and by future history thumbnails.
    public static func image(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

/// Result of a clipboard write, so tests can assert on representations rather than side effects.
public struct MSClipboardPayload: Sendable, Equatable {
    public var png: Data?
    public var tiff: Data?
    public init(png: Data?, tiff: Data?) { self.png = png; self.tiff = tiff }
}

public struct MSClipboardWriter {
    private let pasteboard: any MSPasteboardWriting
    public init(pasteboard: any MSPasteboardWriting) { self.pasteboard = pasteboard }

    /// Encodes off the main thread, then performs exactly one pasteboard write (`ADR-014`).
    @discardableResult
    public func write(_ image: CGImage, scale: Int, pngAndTiff: Bool = true) -> Bool {
        let started = ContinuousClock.now
        let before = pasteboard.changeCount
        let png = MSImageEncoder.png(image, scale: scale)
        let tiff = pngAndTiff ? MSImageEncoder.tiff(image, scale: scale) : nil
        guard let png, pasteboard.writeImage(png: png, tiff: tiff ?? Data()) else {
            MSLog.error(.export, "clipboard write refused")
            return false
        }
        if pasteboard.changeCount == before {
            MSLog.error(.export, "clipboard changeCount unchanged (someone else owns the pasteboard)")
            return false
        }
        MSLog.info(.export, "t.commit→clipboard-ready took \(started.duration(to: ContinuousClock.now)) bytes=\(png.count)")
        return true
    }
}

public struct MSExportRequest: Sendable {
    public var image: CGImage
    public var scale: Int
    public var format: MSImageFormat
    public var jpegQuality: Double
    public var naming: MSNamingTemplate
    public var date: Date
    public var directory: URL
    public init(image: CGImage, scale: Int, format: MSImageFormat = .png, jpegQuality: Double = 0.9,
                naming: MSNamingTemplate, date: Date = Date(), directory: URL) {
        self.image = image; self.scale = scale; self.format = format; self.jpegQuality = jpegQuality
        self.naming = naming; self.date = date; self.directory = directory
    }
}

public enum MSExportOutcome: Sendable, Equatable {
    case written(path: String, bytes: Int)
    case failed(MSFileError)
}

/// File saving with the "no overwrite within the same second" rule from `FR-EXP-003`.
public struct MSFileExporter {
    private let writer: any MSFileWriting
    public init(writer: any MSFileWriting = DiskFileWriter()) { self.writer = writer }

    /// The name the template produces for a given index (index matters only when the template
    /// contains `{index}`; otherwise every call returns the same stem).
    public func url(for request: MSExportRequest, index: Int) -> URL {
        let base = request.naming.expand(.init(date: request.date,
                                               pixelSize: MSIntSize(width: request.image.width, height: request.image.height),
                                               scale: request.scale), index: index)
        return request.directory.appendingPathComponent("\(base).\(request.format.fileExtension)")
    }

    /// Collision-free path. A template without `{index}` must still never overwrite an earlier
    /// capture in the same second (`FR-EXP-003` judgement: 10 rapid saves, 10 distinct files),
    /// so a `-NNN` suffix is appended when the stem is taken.
    public func uniqueURL(for request: MSExportRequest) -> URL {
        let first = url(for: request, index: 1)
        guard writer.fileExists(at: first) else { return first }
        let stem = first.deletingPathExtension().lastPathComponent
        let dir = first.deletingLastPathComponent()
        var index = 2
        while index <= 10_000 {
            let candidate = dir.appendingPathComponent("\(stem)-\(String(format: "%03d", index)).\(request.format.fileExtension)")
            if !writer.fileExists(at: candidate) { return candidate }
            index += 1
        }
        return first
    }

    public func save(_ request: MSExportRequest) -> MSExportOutcome {
        let target = uniqueURL(for: request)
        let data: Data?
        switch request.format {
        case .png: data = MSImageEncoder.png(request.image, scale: request.scale)
        case .jpeg: data = MSImageEncoder.jpeg(request.image, scale: request.scale, quality: request.jpegQuality)
        }
        guard let data else { return .failed(.writeFailed(path: target.path, reason: "encode failed")) }
        do { try writer.write(data, to: target) } catch let error as MSFileError { return .failed(error) }
        catch { return .failed(.writeFailed(path: target.path, reason: error.localizedDescription)) }
        MSLog.info(.export, "saved \(target.lastPathComponent) bytes=\(data.count)")
        return .written(path: target.path, bytes: data.count)
    }
}
