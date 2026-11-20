import CoreGraphics
import Foundation
import Testing
@testable import MSCapture

/// 11-20 用户实测：检查更新后再截图，屏幕上出现一个写着 "permission" 的灰块，之后截图一直不可用。
/// 根因之一在这里——旧判据只看"五个取样点全等"，于是一张白底文档（白边 + 白底）被当成"没权限"。
/// 无权限的真实签名是**纯黑帧**（终端未授权时实测五点全 `0,0,0`），所以判据必须是"均匀 且 接近纯黑"。
struct DegenerateFrameTests {
    @MainActor
    private func uniform(_ red: UInt8, _ green: UInt8, _ blue: UInt8, width: Int = 64, height: Int = 48) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ctx.makeImage())
    }

    /// 上下两半不同色：任何"全等"判据都必须放它过去。
    @MainActor
    private func twoTone() throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 24))
        return try #require(ctx.makeImage())
    }

    @MainActor
    @Test("纯黑均匀帧＝没权限的签名，判 degenerate")
    func blackUniformIsDegenerate() throws {
        #expect(MSCaptureDiagnostics.isDegenerate(try uniform(0, 0, 0)))
    }

    @MainActor
    @Test("纯白均匀帧是合法画面，不许报成权限问题")
    func whiteUniformIsNotDegenerate() throws {
        #expect(!MSCaptureDiagnostics.isDegenerate(try uniform(255, 255, 255)))
    }

    @MainActor
    @Test("近白与浅灰文档底也不许误判")
    func lightUniformIsNotDegenerate() throws {
        for tone in [UInt8(240), 250, 254] {
            #expect(!MSCaptureDiagnostics.isDegenerate(try uniform(tone, tone, tone)))
        }
    }

    @MainActor
    @Test("非均匀帧永远不是 degenerate")
    func mixedIsNotDegenerate() throws {
        #expect(!MSCaptureDiagnostics.isDegenerate(try twoTone()))
    }
}
