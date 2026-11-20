import Foundation
import AppKit
import Testing
@testable import MSCapture
@testable import MSCore
@testable import MSExport
@testable import MSPin
@testable import MSSession
@testable import MSSettings
@testable import MSTestSupport

/// 11-20 用户实测的第二个根因：`reportCaptureFailure` 以前对**任何**采集失败都无条件调
/// `onNeedsPermission`，于是"display 找不到 / 后端报错 / 空帧"全都谎称"缺屏幕录制权限"，
/// 权限窗开过一次之后就把后续截图一直挡住。这里钉两件事：
/// ① 非权限失败不许开权限窗，且下一次截图照样能用；② 权限失败的文案必须是人话，不是内部 token。
struct CaptureFailureHonestyTests {
    /// 数组是值类型：以前这里把 `toasts` 直接放进返回元组，拿到的是**返回那一刻的快照**，
    /// 之后闭包再怎么追加都看不见 ⇒ 断言永远读到空数组（假绿的反面：假红）。
    @MainActor
    private final class Recorder {
        var toasts: [String] = []
        var gates = 0
    }

    @MainActor
    private func makeCoord(failingWith error: Error) throws -> (MSSessionCoordinator, Recorder) {
        let display = try #require(MSDisplayInventory.current().first, "测试环境必须有显示器")
        let ctx = try #require(CGContext(data: nil, width: display.pixelSize.width, height: display.pixelSize.height,
                                         bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: display.pixelSize.width, height: display.pixelSize.height))
        let capturer = MSFakeCapturer(image: try #require(ctx.makeImage()))
        capturer.failure = error
        let coord = MSSessionCoordinator(capturer: capturer, preferences: MSFakePreferences(),
                                         pins: MSPinRegistry(), clipboard: MSClipboardWriter(pasteboard: MSFakePasteboard()))
        coord.presentsOverlay = false
        let rec = Recorder()
        coord.onToast = { rec.toasts.append($0) }
        coord.onNeedsPermission = { rec.gates += 1 }
        return (coord, rec)
    }

    @MainActor
    private func settle(_ coord: MSSessionCoordinator) async throws {
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(20))
            if coord.sessionPhaseName == "idle" || coord.sessionPhaseName == "failed" { break }
        }
    }

    @MainActor
    @Test("display 找不到 ⇒ 只说失败，不开权限窗，下一次截图还能用")
    func nonPermissionFailureDoesNotOpenGate() async throws {
        let (coord, rec) = try makeCoord(failingWith: MSCaptureError.displayNotFound(42))
        coord.handle(.snip)
        try await settle(coord)
        #expect(rec.gates == 0)
        #expect(rec.toasts.first?.contains("截图失败") == true)
        #expect(rec.toasts.first?.contains("permission") == false)
        // 会话必须回到 idle：再按一次截图键要能重新发起采集，而不是永远卡在权限那页。
        let before = coord.captureAttempts
        coord.handle(.snip)
        try await settle(coord)
        #expect(coord.captureAttempts > before)
    }

    @MainActor
    @Test("后端报错（非 -3801）同样不许谎称缺权限")
    func backendFailureDoesNotOpenGate() async throws {
        let (coord, rec) = try makeCoord(failingWith: MSCaptureError.backend("SCStreamErrorDomain 其它码"))
        coord.handle(.snip)
        try await settle(coord)
        #expect(rec.gates == 0)
    }

    @MainActor
    @Test("系统说权限已给 ⇒ 就不许再谎称缺权限（11-20 那次正是这个自相矛盾）")
    func grantedButEmptyFrameDoesNotGate() async throws {
        let (coord, rec) = try makeCoord(failingWith: MSCaptureError.permissionMissing)
        coord.permissionRequester = { .granted }
        coord.handle(.snip)
        try await settle(coord)
        #expect(rec.gates == 0)
        #expect(rec.toasts.first?.contains("空画面") == true)

        // 反证：同一支错误，但系统回答是 denied ⇒ 权限窗必须开（这条守卫不许把真缺权限也吞掉）
        let (coord2, rec2) = try makeCoord(failingWith: MSCaptureError.permissionMissing)
        coord2.permissionRequester = { .denied }
        coord2.handle(.snip)
        try await settle(coord2)
        #expect(rec2.gates == 1)
        #expect(rec2.toasts.first == MSSessionCoordinator.permissionHint)
    }

    @MainActor
    @Test("真权限失败 ⇒ 开一次权限窗，文案是人话而不是内部 token")
    func permissionFailureGatesWithHumanText() async throws {
        let (coord, rec) = try makeCoord(failingWith: MSCaptureError.permissionMissing)
        // 把"系统的回答"钉成 denied：这才是真缺权限的形状。留空的话会去读真 TCC，
        // 本机是 granted ⇒ 新守卫会走"空画面"那一支，测试意图就被环境吃掉了。
        coord.permissionRequester = { .denied }
        coord.handle(.snip)
        try await settle(coord)
        #expect(rec.gates == 1)
        let text = rec.toasts.first ?? ""
        #expect(text == MSSessionCoordinator.permissionHint)
        #expect(text.contains("屏幕录制"))
        #expect(text != "permission")
    }
}
