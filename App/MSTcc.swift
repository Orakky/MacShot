import Foundation
import MSCore

/// TCC 复位。用途很窄但很关键：用户误点一次"稍后/拒绝"之后，系统不再弹框，
/// 列表项锁死在已拒绝状态，`tccutil reset` 是唯一不需要重装系统的出路。
enum MSTcc {
    @discardableResult
    static func resetScreenCapture(bundleID: String = Bundle.main.bundleIdentifier ?? "com.macshot.app") -> Bool {
        // 参数全是常量，不拼用户输入。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            MSLog.info(.app, "tccutil reset ScreenCapture \(bundleID) status=\(process.terminationStatus)")
            return process.terminationStatus == 0
        } catch {
            MSLog.error(.app, "tccutil reset failed: \(error.localizedDescription)")
            return false
        }
    }
}
