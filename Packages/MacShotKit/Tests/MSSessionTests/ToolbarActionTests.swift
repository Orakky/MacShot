import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import MSSettings
import Testing
@testable import MSOverlay

/// 用户 11-18 报的第 1 条：**操作栏里的"贴出/保存/取消"点了没反应**。
/// 成因不是按钮坏了，是压根没有按钮——那串字只是 `draw(at:)` 画上去的，
/// 而 `hitToolbar` 对整条矩形一律返回"被工具条吃掉"，所以点它和点空白一模一样。
/// 判据一律走真事件喂 `mouseDown`，看委托收到什么意图，不看内部状态变量。
struct ToolbarActionTests {
    @MainActor
    private final class Spy: MSOverlayDelegate {
        var intents: [MSCommitIntent] = []
        var cancels = 0
        var prefs = MSAppPreferences()
        func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) { intents.append(intent) }
        func overlayDidCancel(_ overlay: MSOverlayWindow) { cancels += 1 }
        func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {}
        func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase) {}
        func overlay(_ overlay: MSOverlayWindow, didPickColor text: String) {}
        func overlay(_ overlay: MSOverlayWindow, elementCount: Int) {}
        func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage? { nil }
        func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences { prefs }
    }

    /// 400×250 的假显示器放不下整条工具条（`showsActions` 会先收掉动作文字），
    /// 所以这里用一张 1600×1000@1x 的——测的正是"动作格画出来时能不能点"。
    private static let display = MSDisplay(id: 99, logicalFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                                           visibleFrame: CGRect(x: 0, y: 24, width: 1600, height: 976),
                                           scale: 1, isMain: true, localizedName: "Wide Test Display")

    @MainActor
    private func makeWindow(prefs: MSAppPreferences = .init()) throws -> (MSOverlayWindow, MSOverlayView, Spy) {
        let ctx = CGContext(data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
        let window = MSOverlayWindow(display: Self.display, frame: ctx.makeImage()!)
        let view = window.overlayView
        let spy = Spy(); spy.prefs = prefs
        window.overlayDelegate = spy
        view.setSelection(CGRect(x: 100, y: 100, width: 900, height: 600))
        view.needsDisplay = true
        _ = view.bitmapImageRepForCachingDisplay(in: view.bounds).map { view.cacheDisplay(in: view.bounds, to: $0) }
        return (window, view, spy)
    }

    private func mid(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    @MainActor
    private func click(_ view: MSOverlayView, _ p: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let realH = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                         mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
        view.mouseDown(with: NSEvent(cgEvent: cg)!)
        view.mouseUp(with: {
            let c = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                            mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
            return NSEvent(cgEvent: c)!
        }())
    }

    @MainActor
    private func box(_ view: MSOverlayView, _ action: MSAnnotationToolbar.BarAction) throws -> CGRect {
        let boxes = view.actionBoxesForProbe
        #expect(boxes.count == MSAnnotationToolbar.BarAction.allCases.count,
                "动作格数量不对（画了才有条，先自绘一次）：\(boxes.map(\.action))")
        return try #require(boxes.first { $0.action == action }?.rect, "没有 \(action.rawValue) 这一格")
    }

    @MainActor
    @Test("点「贴出」＝按 Enter：默认档发 .pin；设置改成「复制」后按钮动词与意图一起跟着变")
    func commitButtonFollowsTheSetting() throws {
        let (_, view, spy) = try makeWindow()
        click(view, mid(try box(view, .commit)))
        #expect(spy.intents == [.pin], "点贴出没发出 .pin，got=\(spy.intents)")

        var copyPrefs = MSAppPreferences(); copyPrefs.commitBehavior = .copy
        let (_, view2, spy2) = try makeWindow(prefs: copyPrefs)
        let label = try #require(view2.actionBoxesForProbe.first { $0.action == .commit })
        click(view2, mid(label.rect))
        #expect(spy2.intents == [.copy], "设置=复制 时按钮还发 .pin ⇒ 写着「贴出」却复制，自相矛盾")
        #expect(label.action.label(verb: copyPrefs.commitBehavior.shortLabel).contains("复制"),
                "按钮文字没跟随设置，got=\(label.action.label(verb: copyPrefs.commitBehavior.shortLabel))")
    }

    @MainActor
    @Test("复制 / 保存 / 取消 三格各自路由；条内空白仍然什么都不会发生")
    func otherButtonsRoute() throws {
        let (_, view, spy) = try makeWindow()
        click(view, mid(try box(view, .copy)))
        #expect(spy.intents == [.copy])
        click(view, mid(try box(view, .save)))
        #expect(spy.intents == [.copy, .savePanel], "保存该走 ⌘S 同一条路（savePanel），got=\(spy.intents)")
        click(view, mid(try box(view, .cancel)))
        #expect(spy.cancels == 1, "点取消必须真退出，got=\(spy.cancels)")

        // 对照：色板与动作格之间的空白——整条仍不许漏下去开新选区
        let layout = try #require(view.actionBoxesForProbe.first?.rect)
        let blank = CGPoint(x: layout.minX - 40, y: layout.midY)
        let before = spy.intents.count
        click(view, blank)
        #expect(spy.intents.count == before && view.selection != nil, "点条内空白不该触发任何动作，也不该重开选区")
    }

    @MainActor
    @Test("没有选区时点「贴出」不派发（与 Enter 同一条守卫）")
    func commitWithoutSelectionIsRefused() throws {
        let (_, view, spy) = try makeWindow()
        let boxes = view.actionBoxesForProbe
        view.setSelection(nil)
        guard let commit = boxes.first(where: { $0.action == .commit })?.rect else {
            Issue.record("自绘后拿不到动作格"); return
        }
        click(view, mid(commit))
        #expect(spy.intents.isEmpty, "没有选区却派发了 \(spy.intents)")
    }
}
