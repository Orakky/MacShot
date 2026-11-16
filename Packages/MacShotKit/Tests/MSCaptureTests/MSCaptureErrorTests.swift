import Foundation
import Testing
@testable import MSCapture

/// 2026-11-16 事故取证：SCK 把"没给屏幕录制权限"报成 NSError
/// `com.apple.ScreenCaptureKit.SCStreamErrorDomain -3801`，不是我们的类型。
/// 不归类就会落到通用 catch：既不触发系统授权流程，又把 NSError 原文甩到用户屏幕上。
struct MSCaptureErrorClassificationTests {
    private func sckError(_ code: Int) -> NSError {
        NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: code,
                userInfo: [NSLocalizedDescriptionKey: "用户拒绝了应用程序、窗口、显示器捕捉的TCC"])
    }

    @Test("-3801 判为权限缺失")
    func userRejectedIsPermission() {
        #expect(MSCaptureError.isPermissionDenied(sckError(MSCaptureError.sckUserRejected)))
    }

    @Test("其它 SCK 错误不得误判为权限（否则会把配置问题说成没授权）")
    func otherSCKErrorsAreNotPermission() {
        #expect(!MSCaptureError.isPermissionDenied(sckError(-3000)))
        #expect(!MSCaptureError.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: 1)))
    }

    @Test("我们自己的 permissionMissing 也算")
    func ownErrorCounts() {
        #expect(MSCaptureError.isPermissionDenied(MSCaptureError.permissionMissing))
    }

    @Test("describe 不含像素内容，只有 domain/code/文案")
    func describeIsLogSafe() {
        let text = MSCaptureError.describe(sckError(-3801))
        #expect(text.contains("-3801"))
        #expect(text.count < 200)
    }
}
