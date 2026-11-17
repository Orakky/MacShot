import AppKit
import CoreGraphics
import Foundation
import Testing
import MSCore
import MSCapture
import MSAnnotate
import MSTestSupport
import MSHotKey
import MSPin
import MSExport
import MSSettings
@testable import MSOverlay
@testable import MSSession

/// `A-11`「设置真的生效」。以前的测试只证明**存下来了**（`MSSettingsTests` 的往返），
/// 而"改了行为跟着变"一条都没有——`annotationStyle()` 就是在这种绿底下没人调用，
/// 用户改描边色/线宽/字号/模糊半径全都不生效（`E-069`）。
/// 这里的判据一律走生产入口：会话建窗、真事件绘制、真写盘。
struct SettingsTakeEffectTests {
    @MainActor
    private func session(prefs: MSAppPreferences) async throws -> (MSSessionCoordinator, MSFakePasteboard, MSPinRegistry, MSOverlayWindow) {
        let pb = MSFakePasteboard()
        let pins = MSPinRegistry()
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(image: try displaySizedImage()),
                                         preferences: MSFakePreferences(current: prefs),
                                         pins: pins, clipboard: MSClipboardWriter(pasteboard: pb))
        coord.presentsOverlay = false
        coord.handle(.snip)
        for _ in 0..<40 where !coord.overlayVisible { try await Task.sleep(for: .milliseconds(25)) }
        let window = try #require(coord.overlay)
        return (coord, pb, pins, window)
    }

    @MainActor
    private func displaySizedImage() throws -> CGImage {
        let display = try #require(MSDisplayInventory.current().first, "测试环境必须有显示器")
        let ctx = CGContext(data: nil, width: display.pixelSize.width, height: display.pixelSize.height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(120, 160, 200).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: display.pixelSize.width, height: display.pixelSize.height))
        return try #require(ctx.makeImage())
    }

    @MainActor
    private func select(_ coord: MSSessionCoordinator, _ window: MSOverlayWindow, _ rect: CGRect) {
        window.overlayView.setSelection(rect)
        coord.overlay(window, selectionDidChange: rect)
    }

    @MainActor
    @Test("默认样式四项（描边色 / 线宽 / 字号 / 模糊半径）从设置装进视图，并落到画出来的元素上")
    func annotationDefaultsReachTheElements() async throws {
        var prefs = MSAppPreferences()
        prefs.annotationDefaults.strokeHex = "#123456"
        prefs.annotationDefaults.lineWidth = 7
        prefs.annotationDefaults.fontSize = 24
        prefs.annotationDefaults.blurRadius = 30
        let (coord, _, _, window) = try await session(prefs: prefs)
        let view = window.overlayView
        select(coord, window, CGRect(x: 20, y: 20, width: 300, height: 200))
        #expect(view.colorHex == "#123456", "建窗时没应用设置里的描边色，got=\(view.colorHex)")
        #expect(view.lineWidth == 7 && view.fontSize == 24 && view.blurRadius == 30,
                "四项里至少一项没应用：\(view.lineWidth)/\(view.fontSize)/\(view.blurRadius)")

        // 真事件画一笔，检查元素拿到的是设置里的样式，而不是视图里的字面量
        view.tool = .rect
        let src = CGEventSource(stateID: .combinedSessionState)
        let realH = NSScreen.screens.first?.frame.height ?? 1080
        func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
            let cg = CGEvent(mouseEventSource: src, mouseType: type,
                             mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
            return NSEvent(cgEvent: cg)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 80, y: 180)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 220, y: 60)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 220, y: 60)))
        let drawn = try #require(view.document?.elements.last, "一笔都没画出来，这条判据就是空的")
        #expect(drawn.style.lineWidth == 7, "元素线宽不是设置值，got=\(drawn.style.lineWidth)")
        #expect(drawn.style.stroke.hex().uppercased() == "#123456",
                "元素描边色不是设置值，got=\(drawn.style.stroke.hex())")
    }

    @MainActor
    @Test("提交动作改成「复制」后 Enter 只写剪贴板不贴图，⌘P 仍然贴出")
    func commitBehaviorSettingRoutesEnter() async throws {
        var prefs = MSAppPreferences()
        prefs.commitBehavior = .copy
        let (coord, pb, pins, window) = try await session(prefs: prefs)
        select(coord, window, CGRect(x: 10, y: 10, width: 120, height: 80))
        // 真按 Enter：意图必须由**设置**决定，而不是测试替它挑一个。
        func press(_ code: UInt16, _ flags: CGEventFlags = []) -> NSEvent {
            let cg = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
                             virtualKey: CGKeyCode(code), keyDown: true)!
            cg.flags = flags
            return NSEvent(cgEvent: cg)!
        }
        window.overlayView.keyDown(with: press(36))                       // Enter
        for _ in 0..<40 where pb.writeCount == 0 { try await Task.sleep(for: .milliseconds(25)) }
        #expect(pb.writeCount == 1, "设置=.copy 时 Enter 必须写剪贴板")
        #expect(pins.count == 0, "设置=.copy 时 Enter 不该贴图：pins=\(pins.count)")

        // 同一条 Enter 在默认档（.pin）下必须贴出——否则上面那条 0 什么都证明不了
        let (coord2, pb2, pins2, window2) = try await session(prefs: MSAppPreferences())
        select(coord2, window2, CGRect(x: 10, y: 10, width: 120, height: 80))
        window2.overlayView.keyDown(with: press(36))
        #expect(pins2.count == 1, "默认档 Enter 必须贴出，got=\(pins2.count)")
        #expect(pb2.writeCount == 1, "默认档 Enter 顺带复制（Q-05）")

        // ⌘P 是固定出口，不跟随设置
        let (coord3, _, pins3, window3) = try await session(prefs: prefs)
        select(coord3, window3, CGRect(x: 10, y: 10, width: 120, height: 80))
        window3.overlayView.keyDown(with: press(35, .maskCommand))
        #expect(pins3.count == 1, "⌘P 必须仍然贴出，got=\(pins3.count)")
    }

    @MainActor
    @Test("导出目录与命名模板改了之后，⌘⇧S 真的写到那个目录、按那个名字")
    func exportSettingsReachTheFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macshot-settings-\(UUID().uuidString)")
        var prefs = MSAppPreferences()
        prefs.export.directory = dir.path
        prefs.export.namingTemplate = "T-{width}x{height}"
        let (coord, _, _, window) = try await session(prefs: prefs)
        select(coord, window, CGRect(x: 10, y: 10, width: 120, height: 80))
        coord.overlay(window, didRequest: .quickSave)
        for _ in 0..<60 {
            if ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).contains(where: { $0.hasPrefix("T-") }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(names.contains(where: { $0.hasPrefix("T-") && $0.hasSuffix(".png") }),
                "命名模板没生效或没写进这个目录：dir=\(dir.path) 内容=\(names)")
        try? FileManager.default.removeItem(at: dir)
    }
}
