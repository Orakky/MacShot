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
    @MainActor
    @Test("明暗设置真的换掉遮罩 chrome：dark 压得更暗、light 更亮，system 交回系统")
    func appearanceSettingChangesTheChrome() async throws {
        func readout(_ a: MSAppPreferences.Appearance) async throws -> (dark: Bool, alpha: CGFloat, lum: Int) {
            var prefs = MSAppPreferences()
            prefs.appearance = a
            let (coord, _, _, window) = try await session(prefs: prefs)
            select(coord, window, CGRect(x: 40, y: 40, width: 320, height: 200))
            let view = window.overlayView
            if a != .system {
                // 前置对照：设置必须真落到窗上，否则下面的读数只是系统外观的成绩
                #expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                        == (a == .dark ? NSAppearance.Name.darkAqua : NSAppearance.Name.aqua),
                        "appearance=\(a) 没落到窗口上")
            }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                Issue.record("拿不到位图"); return (false, 0, 0)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            let shown = try #require(rep.colorAt(x: Int(20 * scale), y: Int((view.bounds.height - 20) * scale)))
            return (view.chromeIsDark, OverlayChrome.scrimAlpha(isDark: view.chromeIsDark),
                    Int(((shown.redComponent + shown.greenComponent + shown.blueComponent) * 100).rounded()))
        }
        let dark = try await readout(.dark)
        let light = try await readout(.light)
        #expect(dark.dark && dark.alpha == 0.55, "深色档应 chromeIsDark=true、scrim=0.55，got=\(dark)")
        #expect(!light.dark && light.alpha == 0.45, "浅色档应 chromeIsDark=false、scrim=0.45，got=\(light)")
        // 像素判据（V-044）：同一处画面，深色档必须压得更暗
        #expect(dark.lum < light.lum, "深色档并没有更暗：dark=\(dark.lum) light=\(light.lum)")

        let (coord, _, _, window) = try await session(prefs: MSAppPreferences())   // 默认 .system
        #expect(window.appearance == nil, ".system 档必须把窗口外观交回系统，got=\(String(describing: window.appearance))")
    }

    @MainActor
    @Test("「拖拽时显示放大镜」关掉后拖框不再自动弹，但 ⌥ 仍能强制呼出")
    func magnifierToggleGatesTheDragCase() async throws {
        var prefs = MSAppPreferences()
        prefs.showMagnifierWhileDragging = false
        let (coord, _, _, window) = try await session(prefs: prefs)
        let view = window.overlayView
        #expect(!view.autoLoupeWhileDragging, "设置没落到视图上，这条判据就是空的")
        select(coord, window, CGRect(x: 30, y: 30, width: 260, height: 180))

        let src = CGEventSource(stateID: .combinedSessionState)
        let realH = NSScreen.screens.first?.frame.height ?? 1080
        func mouse(_ type: CGEventType, _ p: CGPoint, option: Bool = false) -> NSEvent {
            let cg = CGEvent(mouseEventSource: src, mouseType: type,
                             mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
            if option { cg.flags = CGEventFlags.maskAlternate }
            return NSEvent(cgEvent: cg)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 120, y: 120)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 200, y: 80)))
        view.mouseMoved(with: mouse(.mouseMoved, CGPoint(x: 200, y: 80)))
        #expect(!view.isLoupeVisible, "开关关了还自动弹放大镜 ⇒ 这个设置等于没做")

        view.mouseMoved(with: mouse(.mouseMoved, CGPoint(x: 200, y: 80), option: true))
        #expect(view.isLoupeVisible, "⌥ 强制是另一条路，不该被这个开关关掉")
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 200, y: 80)))

        // 对照：默认档开着，拖框必须自动弹——否则上面那条"不弹"什么也没证明
        let (coord2, _, _, window2) = try await session(prefs: MSAppPreferences())
        let view2 = window2.overlayView
        select(coord2, window2, CGRect(x: 30, y: 30, width: 260, height: 180))
        view2.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 120, y: 120)))
        view2.mouseMoved(with: mouse(.mouseMoved, CGPoint(x: 200, y: 80)))
        #expect(view2.autoLoupeWhileDragging && view2.isLoupeVisible, "默认档拖框应自动出现放大镜")
    }
}
