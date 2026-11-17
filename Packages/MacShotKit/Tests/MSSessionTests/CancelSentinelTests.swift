import CoreGraphics
import Foundation
import Testing
import MSCore
import MSTestSupport
import MSHotKey
import MSPin
import MSExport
@testable import MSSession

/// `FR-SESS-002` 判据④：取消会话**一次都不许**碰剪贴板。
/// 这是实现里最容易犯的错——"顺手复制一下反正用户不会介意"。
struct CancelSentinelTests {
    @MainActor
    @Test("取消路径不写剪贴板，且遮罩确实开过（防空断言）")
    func cancelNeverWritesPasteboard() async throws {
        let pb = MSFakePasteboard()
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(),
                                         preferences: MSFakePreferences(),
                                         pins: MSPinRegistry(),
                                         clipboard: MSClipboardWriter(pasteboard: pb))
        coord.handle(.snip)
        // 假采集也是 async：等它把遮罩立起来，否则"没写剪贴板"可能只是因为压根没进会话
        for _ in 0..<20 where !coord.overlayVisible {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(coord.overlayVisible, "遮罩没起来的话这条判据就是空的")

        coord.cancelSession()
        #expect(!coord.overlayVisible)
        #expect(pb.writeCount == 0, "取消路径写了 \(pb.writeCount) 次剪贴板")
        // 再取消一次也不该补写（幂等）
        coord.cancelSession()
        #expect(pb.writeCount == 0)
    }

    @MainActor
    @Test("对照：复制出口必须真写一次，否则上面的 0 没有意义")
    func copyPathDoesWrite() throws {
        let pb = MSFakePasteboard()
        let writer = MSClipboardWriter(pasteboard: pb)
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(10, 132, 255).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let ok = writer.write(ctx.makeImage()!, scale: 1)
        #expect(ok)
        #expect(pb.writeCount == 1, "哨兵假剪贴板必须真能被写，不然 0 是假的")
    }
}
