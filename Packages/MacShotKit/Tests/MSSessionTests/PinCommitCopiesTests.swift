import CoreGraphics
import Foundation
import Testing
import MSCore
import MSCapture
import MSTestSupport
import MSHotKey
import MSOverlay
import MSPin
import MSExport
@testable import MSSession

/// `Q-05` / `FR-PIN-018`：「置顶」这个出口**本身就带复制**。
/// 两条判据方向相反、必须同时在：`Enter` 要写剪贴板，`Esc` 一次都不许写（`CancelSentinelTests`）。
/// 入口走的是遮罩委托 `overlay(_:didRequest:)`——那才是生产路径，绕过它去调私有函数等于没测。
struct PinCommitCopiesTests {
    /// 选区必须**同时**告诉视图和会话：生产里是拖出来的，两边都会收到；
    /// 只设视图的话 `hasSelection` 还是 false，会话会回一句"先框选区域"然后什么都不做。
    @MainActor
    private func select(on coord: MSSessionCoordinator, window: MSOverlayWindow) {
        let rect = CGRect(x: 10, y: 10, width: 120, height: 80)
        window.overlayView.setSelection(rect)
        coord.overlay(window, selectionDidChange: rect)
    }

    /// 假采集必须给**显示器像素尺寸**的图：`RegionCropper` 按显示器的 scale 把逻辑选区换成像素矩形，
    /// 8×8 的默认夹具会被判"选区无效"而整条 commit 静默返回——测试就会绿得没意义（今天栽过）。
    @MainActor
    private func displaySizedImage() throws -> CGImage {
        let display = try #require(MSDisplayInventory.current().first, "测试环境必须有至少一台显示器")
        let ctx = CGContext(data: nil, width: display.pixelSize.width, height: display.pixelSize.height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(120, 160, 200).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: display.pixelSize.width, height: display.pixelSize.height))
        return try #require(ctx.makeImage())
    }

    @MainActor
    private func makeSession() async throws -> (MSSessionCoordinator, MSFakePasteboard, MSPinRegistry) {
        let pb = MSFakePasteboard()
        let pins = MSPinRegistry()
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(image: try displaySizedImage()),
                                         preferences: MSFakePreferences(),
                                         pins: pins, clipboard: MSClipboardWriter(pasteboard: pb))
        coord.presentsOverlay = false                 // 测试不许劫持人的屏幕（B-029 / T-099）
        coord.handle(.snip)
        for _ in 0..<20 where !coord.overlayVisible {
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = try #require(coord.overlay, "遮罩窗没建起来的话，下面的 0 次和 1 次都是空的")
        return (coord, pb, pins)
    }

    @MainActor
    @Test("Enter＝贴出并复制：一次会话同时产出贴图与剪贴板 PNG")
    func pinAlsoCopies() async throws {
        let (coord, pb, pins) = try await makeSession()
        let window = try #require(coord.overlay)
        select(on: coord, window: window)
        var toasts: [String] = []
        coord.onToast = { toasts.append($0) }
        coord.overlay(window, didRequest: .pin)
        #expect(pins.count == 1, "贴图必须开出来；toasts=\(toasts)")
        #expect(pb.writeCount == 1, "置顶必须顺手写一次剪贴板，got=\(pb.writeCount)")
        let png = try #require(pb.writtenPNG, "写进去的必须是 PNG 载荷")
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "剪贴板里的容器必须是 PNG")
        #expect(!coord.overlayVisible, "会话结束后遮罩要关掉")
    }

    @MainActor
    @Test("⌘C 只复制不贴出——两个出口的差别不能被「置顶带复制」抹平")
    func copyDoesNotPin() async throws {
        let (coord, pb, pins) = try await makeSession()
        let window = try #require(coord.overlay)
        select(on: coord, window: window)
        coord.overlay(window, didRequest: .copy)
        // 复制出口把编码放进 Task（大图不该冻住主线程），所以判据要等它，而不是等完再判。
        for _ in 0..<40 where pb.writeCount == 0 { try await Task.sleep(for: .milliseconds(25)) }
        #expect(pb.writeCount == 1)
        #expect(pins.count == 0, "复制出口不许顺手开贴图")
    }

    @MainActor
    @Test("取消出口仍然一次都不写（与 pin 带复制方向相反，两条都要在）")
    func cancelStillNeverWrites() async throws {
        let (coord, pb, pins) = try await makeSession()
        let window = try #require(coord.overlay)
        select(on: coord, window: window)
        coord.overlay(window, didRequest: .cancel)
        #expect(pb.writeCount == 0, "取消路径写了 \(pb.writeCount) 次剪贴板")
        #expect(pins.count == 0)
    }
}
