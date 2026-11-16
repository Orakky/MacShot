import AppKit
import Foundation
import MSCore

/// 显示器清单。放在 `MSCapture` 而不是 `MSCore`：读 `NSScreen` 属于环境探测，
/// 而 `MSCore` 必须是纯几何/图像值类型（`modules.md` §1，`check-deps` 会拦 AppKit）。
/// 会话开始时取一次快照，整个会话都用它（FR-SESS-004）。
public enum MSDisplayInventory {
    public static func current() -> [MSDisplay] {
        NSScreen.screens.compactMap { screen -> MSDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                MSLog.error(.capture, "screen without NSScreenNumber: \(screen.localizedName)")
                return nil
            }
            return MSDisplay(id: CGDirectDisplayID(number.uint32Value),
                             logicalFrame: screen.frame,
                             visibleFrame: screen.visibleFrame,
                             scale: screen.backingScaleFactor,
                             isMain: screen.frame.origin == .zero,
                             localizedName: screen.localizedName)
        }
    }

    public static func display(under point: NSPoint, in displays: [MSDisplay]? = nil) -> MSDisplay? {
        let list = displays ?? current()
        return list.first { $0.logicalFrame.contains(point) } ?? list.first
    }

    public static func desktopLogicalFrame(in displays: [MSDisplay]? = nil) -> CGRect {
        (displays ?? current()).map(\.logicalFrame).reduce(.null) { $0.union($1) }
    }
}
