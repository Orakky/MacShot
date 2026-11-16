import AppKit
import Foundation
import MSCapture
import MSCore

// `main.swift` runs on the main thread, so the MainActor assumption here is real, not a bypass.
//
//   MacShot                    → menu bar agent
//   MacShot --probe-capture    → capture once, print the result, exit (V-001/V-019 evidence)
//   MacShot --probe-permission → print TCC state, exit
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

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { MSAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)     // LSUIElement equivalent even when run from DerivedData
app.run()
