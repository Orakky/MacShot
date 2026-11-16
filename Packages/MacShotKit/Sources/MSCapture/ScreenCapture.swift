import CoreGraphics
import Foundation
import MSCore
import ScreenCaptureKit

public enum MSCaptureError: Error, Equatable, Sendable {
    case displayNotFound(CGDirectDisplayID)
    case permissionMissing
    case emptyFrame(width: Int, height: Int)
    case backend(String)
}

/// The seam every capture test is written against: `MSTestSupport` hands back a known pixel card
/// so pixel-accuracy assertions never need a real screen (`overview.md` §7).
public protocol ScreenCapturing: Sendable {
    func freeze(display: MSDisplay) async throws -> MSCaptureFrame
}

public enum CaptureBackend: String, Sendable { case screenCaptureKit, coreGraphics }

/// One frame per session, single display, no live stream (`ADR-007` + `ADR-008`).
public struct ScreenCaptureKitCapturer: ScreenCapturing {
    public let showsCursor: Bool
    public init(showsCursor: Bool = false) { self.showsCursor = showsCursor }

    public func freeze(display: MSDisplay) async throws -> MSCaptureFrame {
        let started = ContinuousClock.now
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else {
            throw MSCaptureError.displayNotFound(display.id)
        }
        let size = display.pixelSize
        let config = SCStreamConfiguration()
        config.width = max(1, size.width)
        config.height = max(1, size.height)
        config.showsCursor = showsCursor
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let elapsed = started.duration(to: ContinuousClock.now)
        MSLog.info(.capture, "freeze display=\(display.id) \(image.width)x\(image.height) scale=\(display.scale) took=\(elapsed)")
        guard image.width > 0, image.height > 0 else {
            throw MSCaptureError.emptyFrame(width: image.width, height: image.height)
        }
        if await MainActor.run(body: { MSCaptureDiagnostics.isDegenerate(image) }) {
            MSLog.error(.capture, "capture.perm-missing suspected: frame is uniform (display=\(display.id))")
            throw MSCaptureError.permissionMissing
        }
        return .fullDisplay(image, display: display)
    }
}

/// CoreGraphics fallback. Chosen once at launch, never per attempt, so a half-broken permission
/// state cannot produce "sometimes it works" behaviour (`ADR-007` 后果, `overview.md` §6).
public struct CoreGraphicsCapturer: ScreenCapturing {
    public init() {}

    public func freeze(display: MSDisplay) async throws -> MSCaptureFrame {
        guard let image = CGDisplayCreateImage(display.id) else {
            MSLog.error(.capture, "capture.perm-missing: CGDisplayCreateImage returned nil")
            throw MSCaptureError.permissionMissing
        }
        return .fullDisplay(image, display: display)
    }
}

public enum CaptureBackendSelector {
    /// Decided at launch and logged; a session never switches backends mid-flight.
    public static func decide(forced: CaptureBackend? = nil) -> CaptureBackend {
        if let forced { MSLog.info(.capture, "capture.backend=\(forced.rawValue) (forced)"); return forced }
        let choice: CaptureBackend = .screenCaptureKit
        MSLog.info(.capture, "capture.backend=\(choice.rawValue)")
        return choice
    }

    public static func makeCapturer(backend: CaptureBackend) -> ScreenCapturing {
        switch backend {
        case .screenCaptureKit: return ScreenCaptureKitCapturer()
        case .coreGraphics: return CoreGraphicsCapturer()
        }
    }
}

/// Cropping that never resamples: everything routes through `MSDisplay.pixelRect(forLogical:)`
/// so the ±1px rules live in exactly one place (`ADR-013`).
public enum RegionCropper {
    public static func crop(_ frame: MSCaptureFrame, logicalSelection: CGRect, in display: MSDisplay) -> MSCaptureFrame? {
        guard let pixel = display.pixelRect(forLogical: logicalSelection) else {
            MSLog.error(.capture, "crop rejected: selection has no pixel overlap")
            return nil
        }
        return frame.cropping(pixel)
    }

    /// Whole display, as a document-ready frame.
    public static func fullDisplay(_ frame: MSCaptureFrame) -> MSCaptureFrame { frame }
}

/// Permission state without pretending to know more than the API tells us
/// (`hotkey-and-permissions.md` §5; exact behaviour is measured by V-021).
public enum PermissionState: String, Sendable { case granted, denied, unknown }

public enum PermissionProbe {
    public static func screenRecording() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Triggers the system prompt / deep-links the settings pane. Returns the post-call state.
    @discardableResult
    public static func requestScreenRecording() -> PermissionState {
        CGRequestScreenCaptureAccess()
        return screenRecording()
    }
}

/// Heuristic guard so a black frame is reported instead of delivered as a "successful" capture.
/// Deliberately conservative: only a completely uniform frame counts, because real desktops are not.
public enum MSCaptureDiagnostics {
    public static func isDegenerate(_ image: CGImage) -> Bool {
        guard let bmp = MSBitmap(image: image), bmp.width > 8, bmp.height > 8 else { return false }
        let probes = [MSIntPoint(x: 1, y: 1),
                      MSIntPoint(x: bmp.width / 2, y: bmp.height / 2),
                      MSIntPoint(x: bmp.width - 2, y: bmp.height - 2),
                      MSIntPoint(x: bmp.width / 4, y: bmp.height * 3 / 4),
                      MSIntPoint(x: bmp.width * 3 / 4, y: bmp.height / 4)]
        let first = probes.compactMap { bmp.sample(pixelAt: $0) }.first
        guard let first else { return true }
        let samples = probes.compactMap { bmp.sample(pixelAt: $0) }
        return samples.allSatisfy { $0.red == first.red && $0.green == first.green && $0.blue == first.blue }
    }
}
