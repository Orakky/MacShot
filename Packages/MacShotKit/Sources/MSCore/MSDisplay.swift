import CoreGraphics
import Foundation

/// One display, as MacShot sees it. Logical frames use AppKit global space
/// (origin: bottom-left of the main display, y growing up); pixel space is always
/// display-local with origin top-left and y growing down.
public struct MSDisplay: Equatable, Sendable, Identifiable {
    public let id: CGDirectDisplayID
    public let logicalFrame: CGRect
    public let visibleFrame: CGRect
    public let scale: CGFloat
    public let isMain: Bool
    public let localizedName: String

    public init(id: CGDirectDisplayID, logicalFrame: CGRect, visibleFrame: CGRect,
                scale: CGFloat, isMain: Bool, localizedName: String) {
        self.id = id
        self.logicalFrame = logicalFrame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.isMain = isMain
        self.localizedName = localizedName
    }

    public var pixelSize: MSIntSize {
        MSIntSize(width: Int((logicalFrame.width * scale).rounded()),
                  height: Int((logicalFrame.height * scale).rounded()))
    }

    /// Full-screen selection for this display, in AppKit global logical space.
    public var fullLogicalSelection: CGRect { logicalFrame }

    /// Converts an AppKit global logical rect into this display's pixel grid.
    /// Returns nil when the rect does not overlap the display at all.
    public func pixelRect(forLogical rect: CGRect) -> MSIntRect? {
        let clamped = rect.intersection(logicalFrame)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return nil }
        let local = CGRect(x: clamped.minX - logicalFrame.minX,
                           y: logicalFrame.maxY - clamped.maxY,
                           width: clamped.width,
                           height: clamped.height)
        let result = MSIntRect(flippedLogical: local, scale: scale)
        let size = pixelSize
        let bounded = MSIntRect(
            x: Swift.min(Swift.max(0, result.minX), size.width),
            y: Swift.min(Swift.max(0, result.minY), size.height),
            width: result.width,
            height: result.height
        )
        return MSIntRect(x: bounded.minX, y: bounded.minY,
                         width: Swift.min(bounded.width, size.width - bounded.minX),
                         height: Swift.min(bounded.height, size.height - bounded.minY))
    }
}
