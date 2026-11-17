import AppKit
import Foundation
import MSCapture
import MSCore

// `main.swift` runs on the main thread, so the MainActor assumption here is real, not a bypass.
//
//   MacShot                    → menu bar agent
//   MacShot --probe-capture    → capture once, print the result, exit (V-001/V-019 evidence)
//   MacShot --probe-permission → print TCC state, exit
//   MacShot --probe-menu       → 打印状态栏菜单行与"权限行是否真挂在菜单上"，exit
// --snip-now：以 LaunchServices 启动的"真 app 身份"立即触发一次截图。
// 用途是权限取证——直接在终端跑二进制会继承 Terminal 的屏幕录制授权，测不出 app 自己的状态。
if CommandLine.arguments.contains("--snip-now") {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { MSAppDelegate(autoSnip: true) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

if CommandLine.arguments.contains("--probe-permission") {
    print("screenRecording=\(PermissionProbe.screenRecording().rawValue)")
    exit(0)
}

if CommandLine.arguments.contains("--probe-capture") {
    let state = PermissionProbe.screenRecording()
    print("permission=\(state.rawValue)")
    let displays = MSDisplayInventory.current()
    print("displays=\(displays.map { "\($0.localizedName):\($0.logicalFrame.width)x\($0.logicalFrame.height)@x\($0.scale)px\($0.pixelSize.width)x\($0.pixelSize.height)" }.joined(separator: ", "))")
    guard let display = displays.first else { print("FAIL no display"); exit(2) }
    let backend = CaptureBackendSelector.decide()
    let capturer = CaptureBackendSelector.makeCapturer(backend: backend)
    Task { @MainActor in
        var durations: [String] = []
        var last: MSCaptureFrame?
        for _ in 0..<5 {
            let started = ContinuousClock.now
            do {
                let frame = try await capturer.freeze(display: display)
                durations.append("\(started.duration(to: ContinuousClock.now))")
                last = frame
            } catch {
                print("FAIL capture: \(error)")
                exit(3)
            }
        }
        guard let frame = last else { exit(3) }
        let degenerate = MSCaptureDiagnostics.isDegenerate(frame.image)
        print("backend=\(backend.rawValue) pixels=\(frame.image.width)x\(frame.image.height) scale=\(frame.scale)")
        print("degenerate=\(degenerate)  (true ⇒ 屏幕录制权限没给或系统拒绝)")
        print("5 次耗时: \(durations.joined(separator: " "))")
        // Pixel probe on a known spot so colour can be eyeballed against the real screen.
        if let bmp = MSBitmap(image: frame.image) {
            let centre = MSIntPoint(x: frame.image.width / 2, y: frame.image.height / 2)
            print("centre pixel = \(bmp.sample(pixelAt: centre)?.hex() ?? "?")")
        }
        exit(degenerate ? 4 : 0)
    }
    dispatchMain()
}

// --dump-chrome <png>：把遮罩界面离屏自绘成 PNG（不采集、不碰 TCC），给"眼睛"补一次账。
if let i = CommandLine.arguments.firstIndex(of: "--dump-chrome") {
    let out = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "build/chrome.png"
    MainActor.assumeIsolated { MSChromeDump.run(to: out) }
}

// --probe-clipboard：合成图真写系统剪贴板并读回类型集合，给 Q-04"只写 PNG"出判据。
if CommandLine.arguments.contains("--probe-clipboard") {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { MSAppDelegate(autoSnip: false) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        MainActor.assumeIsolated { delegate.probeClipboard() }
    }
    app.run()
}

// --probe-pin <ms>：真采集 → 真贴窗 → 编辑态常驻，给 make probe-pin 截那块窗口。
if let i = CommandLine.arguments.firstIndex(of: "--probe-pin") {
    let ms = CommandLine.arguments.count > i + 1 ? (Int(CommandLine.arguments[i + 1]) ?? 4_000) : 4_000
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { MSAppDelegate(autoSnip: false) }
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        MainActor.assumeIsolated { delegate.probePin(thenExitAfter: ms) }
    }
    app.run()
}

// --snip-then-cancel <ms>：开遮罩，到点走与 Esc 同一条取消路径退出（probe-freeze 用）。
if let i = CommandLine.arguments.firstIndex(of: "--snip-then-cancel") {
    let ms = CommandLine.arguments.count > i + 1 ? (Int(CommandLine.arguments[i + 1]) ?? 2_500) : 2_500
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { MSAppDelegate(autoSnip: false) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        MainActor.assumeIsolated { delegate.probeSnipThenCancel(after: ms) }
    }
    app.run()
}

if CommandLine.arguments.contains("--probe-menu") {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { MSAppDelegate(autoSnip: false) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        MainActor.assumeIsolated { delegate.probeStatusMenu() }
        exit(0)
    }
    app.run()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { MSAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)     // LSUIElement equivalent even when run from DerivedData
app.run()
