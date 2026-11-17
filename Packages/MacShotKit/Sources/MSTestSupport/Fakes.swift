import CoreGraphics
import Foundation
import MSAnnotate
import MSCapture
import MSCore
import MSHotKey
import MSSession

/// Deterministic pixel card: every region has a known colour and 1px edges, so pixel-accuracy
/// assertions have an outside referee instead of trusting our own code (`verification.md` §4).
public enum MSTestCard {
    /// Layout of a `width × height` card, all in device pixels:
    /// - left half: red `#E83347`
    /// - right half top: white, bottom: black
    /// - column at x == width/2 is a hard black/white edge for the ±1px test
    public static func image(width: Int = 800, height: Int = 500) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(MSColorRGBA.rgb(232, 51, 71).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(MSColorRGBA.rgb(255, 255, 255).cgColor)
        ctx.fill(CGRect(x: width / 2, y: height / 2, width: width - width / 2, height: height / 2))
        ctx.setFillColor(MSColorRGBA.rgb(0, 0, 0).cgColor)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height / 2))
        return ctx.makeImage()
    }

    public static let display = MSDisplay(id: 1, logicalFrame: CGRect(x: 0, y: 0, width: 400, height: 250),
                                          visibleFrame: CGRect(x: 0, y: 24, width: 400, height: 226),
                                          scale: 2, isMain: true, localizedName: "Test Display")
}

public final class MSFakeCapturer: ScreenCapturing, @unchecked Sendable {
    public let image: CGImage
    public private(set) var callCount = 0
    public var failure: Error?

    public init(image: CGImage? = nil) {
        self.image = image ?? MSTestCard.image() ?? {
            let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            return ctx.makeImage()!
        }()
    }

    public func freeze(display: MSDisplay) async throws -> MSCaptureFrame {
        callCount += 1
        if let failure { throw failure }
        return .fullDisplay(image, display: display)
    }
}

public final class MSFakePasteboard: MSPasteboardWriting, @unchecked Sendable {
    public private(set) var writtenPNG: Data?
    public private(set) var writeCount = 0
    public var changeCount: Int { writeCount }
    public var acceptsWrites = true

    public init() {}

    public private(set) var writtenText: String?

    public func writeText(_ text: String) -> Bool {
        guard acceptsWrites else { return false }
        writtenText = text
        writeCount += 1
        return true
    }

    public func writeImage(png: Data) -> Bool {
        guard acceptsWrites else { return false }
        writtenPNG = png
        writeCount += 1
        return true
    }
}

public final class MSFakeHotKeyService: MSHotKeyServing, @unchecked Sendable {
    public private(set) var registered: [MSHotKeyID: MSKeyCombo] = [:]
    public private(set) var handlers: [MSHotKeyID: @Sendable () -> Void] = [:]
    public var failures: [MSHotKeyID] = []
    public var conflicts: [MSHotKeyID] { failures }

    public init() {}

    @discardableResult
    public func register(_ combo: MSKeyCombo, id: MSHotKeyID, handler: @escaping @Sendable () -> Void) -> MSRegistrationResult {
        if failures.contains(id) { return .alreadyTaken(-9877) }
        registered[id] = combo; handlers[id] = handler
        return .ok
    }

    public func unregister(_ id: MSHotKeyID) { registered[id] = nil; handlers[id] = nil }
    public func unregisterAll() { registered.removeAll(); handlers.removeAll() }

    /// Tests fire hot keys without a keyboard.
    public func trigger(_ id: MSHotKeyID) { handlers[id]?() }
}

public final class MSFakeFileWriter: MSFileWriting, @unchecked Sendable {
    public private(set) var writes: [(url: URL, bytes: Int)] = []
    public var existing: Set<String> = []
    public var shouldFail = false

    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        if shouldFail { throw MSFileError.writeFailed(path: url.path, reason: "simulated") }
        writes.append((url, data.count))
        existing.insert(url.path)
    }

    public func fileExists(at url: URL) -> Bool { existing.contains(url.path) }
}

/// Sample element set reused by annotate and session tests.
public enum MSSamples {
    public static func arrow(canvas: MSIntSize = MSIntSize(width: 400, height: 200)) -> MSAnnotationElement {
        MSAnnotationElement(kind: .arrow,
                            points: [MSIntPoint(x: 20, y: 150), MSIntPoint(x: 300, y: 60)],
                            style: MSAnnotationStyle(stroke: .rgb(232, 51, 71), lineWidth: 4))
    }

    public static func rect(canvas: MSIntSize = MSIntSize(width: 400, height: 200)) -> MSAnnotationElement {
        MSAnnotationElement(kind: .rect,
                            points: [MSIntPoint(x: 10, y: 10), MSIntPoint(x: 120, y: 80)],
                            style: MSAnnotationStyle(stroke: .rgb(10, 132, 255), lineWidth: 2, cornerRadius: 4))
    }

    public static func document(_ elements: [MSAnnotationElement] = [arrow(), rect()]) -> MSAnnotationDocument {
        MSAnnotationDocument(canvasSize: MSIntSize(width: 400, height: 200), elements: elements)
    }
}

/// Session helpers for tests: drive the reducer without any UI.
public enum MSSessionTestSupport {
    public static func drive(_ events: [MSSessionEvent]) -> (final: MSSessionPhase, effects: [MSSessionEffect]) {
        var reducer = MSSessionReducer()
        var all: [MSSessionEffect] = []
        for e in events { all.append(contentsOf: reducer.handle(e)) }
        return (reducer.phase, all)
    }
}
