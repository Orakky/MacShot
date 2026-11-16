import CoreGraphics
import Foundation

/// The result of one grab: the cropped pixel bitmap plus the provenance needed to interpret it
/// (which display, at what backing scale, from which pixel rect of that display).
public struct MSCaptureFrame: Sendable {
    public let image: CGImage
    public let scale: CGFloat
    public let display: MSDisplay?
    /// Where `image` came from, in the display's pixel space. Nil for frames that were not
    /// produced from a single display (colour test card, pasted image, restored history entry).
    public let sourcePixelRect: MSIntRect?
    public let capturedAt: Date

    public init(image: CGImage, scale: CGFloat, display: MSDisplay? = nil,
                sourcePixelRect: MSIntRect? = nil, capturedAt: Date = Date()) {
        self.image = image
        self.scale = scale
        self.display = display
        self.sourcePixelRect = sourcePixelRect
        self.capturedAt = capturedAt
    }

    public var pixelSize: MSIntSize { MSIntSize(width: image.width, height: image.height) }
    public var logicalSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }

    /// A frame covering an entire display.
    public static func fullDisplay(_ image: CGImage, display: MSDisplay) -> MSCaptureFrame {
        MSCaptureFrame(image: image, scale: display.scale, display: display,
                       sourcePixelRect: MSIntRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// Crops inside this frame. The result is the region itself, so pixel data is never resampled.
    public func cropping(_ rect: MSIntRect) -> MSCaptureFrame? {
        let full = MSIntRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let clipped = rect.intersection(full), !clipped.isEmpty,
              let sub = image.cropping(to: clipped.cgRect) else { return nil }
        let moved = sourcePixelRect.map { MSIntRect(x: $0.minX + clipped.minX, y: $0.minY + clipped.minY,
                                                    width: clipped.width, height: clipped.height) }
        return MSCaptureFrame(image: sub, scale: scale, display: display, sourcePixelRect: moved, capturedAt: capturedAt)
    }

    /// Convenience for the overlay: takes an AppKit global logical rect and the display it lives on.
    public func cropping(logicalRect: CGRect, in display: MSDisplay) -> MSCaptureFrame? {
        guard let pixel = display.pixelRect(forLogical: logicalRect) else { return nil }
        guard let sourceRect = sourcePixelRect else { return cropping(MSIntRect(x: 0, y: 0, width: pixel.width, height: pixel.height)) }
        let relative = MSIntRect(x: pixel.minX - sourceRect.minX, y: pixel.minY - sourceRect.minY,
                                 width: pixel.width, height: pixel.height)
        return cropping(relative)
    }
}
