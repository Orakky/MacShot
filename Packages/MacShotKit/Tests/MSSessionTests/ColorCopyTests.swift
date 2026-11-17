import AppKit
import CoreGraphics
import Foundation
import Testing
import MSCore
import MSTestSupport
import MSPin
import MSExport
import MSOverlay
@testable import MSSession

/// `FR-CAP-016` 的后半段：放大镜里按 `C`，串必须**真的进剪贴板**。
/// 视图只负责取样，写剪贴板走会话——这条链路以前没有入口，所以「取色」只能看不能用。
struct ColorCopyTests {
    @MainActor
    private func makeSession() async throws -> (MSSessionCoordinator, MSFakePasteboard, MSOverlayWindow) {
        let pb = MSFakePasteboard()
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(), preferences: MSFakePreferences(),
                                         pins: MSPinRegistry(), clipboard: MSClipboardWriter(pasteboard: pb))
        coord.presentsOverlay = false
        coord.handle(.snip)
        for _ in 0..<40 where !coord.overlayVisible { try await Task.sleep(for: .milliseconds(25)) }
        let window = try #require(coord.overlay)
        return (coord, pb, window)
    }

    @MainActor
    @Test("C 的串写进剪贴板一次，并弹一条「已复制」提示")
    func copyWritesTextOnce() async throws {
        let (coord, pb, window) = try await makeSession()
        var toasts: [String] = []
        coord.onToast = { toasts.append($0) }
        coord.overlay(window, didPickColor: "#E83347")
        #expect(pb.writtenText == "#E83347", "剪贴板收到的不是取样的串，got=\(String(describing: pb.writtenText))")
        #expect(pb.writeCount == 1)
        #expect(toasts == ["已复制 #E83347"], "got=\(toasts)")
        #expect(coord.overlayVisible, "复制颜色不许结束会话（`finishEffects` 误用的回归护栏）")
    }

    @MainActor
    @Test("取不到色时不写剪贴板，只说一句没有")
    func emptyStringDoesNotWrite() async throws {
        let (coord, pb, window) = try await makeSession()
        var toasts: [String] = []
        coord.onToast = { toasts.append($0) }
        coord.overlay(window, didPickColor: "")
        #expect(pb.writeCount == 0, "空串也写一次的话，用户会把上一个剪贴板内容清掉")
        #expect(toasts == ["没有可复制的颜色"], "got=\(toasts)")
    }

    @MainActor
    @Test("⇧C 切格式后复制的是新格式（三档循环）")
    func formatCycleChangesPayload() async throws {
        let view = MSOverlayView(display: MSTestCard.display,
                                 frozenFrame: MSTestCard.image(width: 400, height: 250)!)
        view.frame = CGRect(origin: .zero, size: MSTestCard.display.logicalFrame.size)
        // 放大镜的锚点只能由真事件产生：没有 mouseMoved 就没有取样，复制串是空是**正确行为**。
        let src = CGEventSource(stateID: .combinedSessionState)
        let realH = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                         mouseCursorPosition: CGPoint(x: 200, y: realH - 125), mouseButton: .left)!
        cg.flags = CGEventFlags.maskAlternate
        view.mouseMoved(with: NSEvent(cgEvent: cg)!)
        let first = view.loupeCopyString()
        view.cycleLoupeFormat()
        let second = view.loupeCopyString()
        #expect(first != second && !first.isEmpty && !second.isEmpty, "三档必须给出不同的串，got=\(first)/\(second)")
    }
}
