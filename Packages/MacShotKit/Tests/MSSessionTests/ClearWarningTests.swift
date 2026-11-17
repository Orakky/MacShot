import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
@testable import MSOverlay
import MSPin
import MSExport
import MSSettings
import MSTestSupport
import Testing
@testable import MSSession

/// `M-4` 准出④ / `Q-11` 推荐档 A：改选区尺寸会把标注清空，而**清空必须显式提示**。
/// 这里盯三件事：提示只在真清了东西时出现、文案只有一个家、
/// 以及那条容易写反的顺序——通知必须排在清空**之前**，否则会话看到的 `hasElements` 永远是 false。
struct ClearWarningTests {
    @MainActor
    private final class Spy: MSOverlayDelegate {
        var selectionNotifications: [CGRect?] = []
        /// 收到"选区变了"那一刻，文档里还有几个元素——顺序判据就看这个数
        var elementCountAtNotification: [Int] = []
        var elementCounts: [Int] = []
        var phases: [MSOverlayDrawingPhase] = []
        weak var watched: MSOverlayView?
        func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {
            selectionNotifications.append(rect)
            elementCountAtNotification.append(watched?.document?.elements.count ?? -1)
        }
        func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) {}
        func overlayDidCancel(_ overlay: MSOverlayWindow) {}
        func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase) { phases.append(phase) }
        func overlay(_ overlay: MSOverlayWindow, elementCount: Int) { elementCounts.append(elementCount) }
        func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage? { nil }
        func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences { .init() }
    }

    // MARK: - 状态机（纯逻辑，无窗）

    @Test("行 7：有元素时改选区 ⇒ 提示；没元素时不提示")
    func rowSevenWarnsOnlyWhenElementsExisted() {
        var reducer = MSSessionReducer()
        reducer.handle(.hotKeyPressed(.snip))
        reducer.handle(.overlayShown)
        // 先画了一件
        reducer.handle(.elementCountChanged(1))
        #expect(reducer.hasElements)

        let effects = reducer.handle(.selectionChanged(width: 200, height: 100))
        #expect(effects.contains(.warnClearAnnotations), "有元素被清掉必须提示，got=\(effects)")
        #expect(!reducer.hasElements, "提示之后标志要落回 false，免得下次空清也提示")

        // 再来一次改尺寸：这次没有元素了，不该再提示
        let second = reducer.handle(.selectionChanged(width: 300, height: 150))
        #expect(!second.contains(.warnClearAnnotations), "空清空不该提示，got=\(second)")
    }

    @Test("行 9/10：绘制起止真的把 selecting ⇄ editing 走起来")
    func drawPhasesDriveTheMachine() {
        var reducer = MSSessionReducer()
        reducer.handle(.hotKeyPressed(.snip))
        reducer.handle(.overlayShown)
        reducer.handle(.selectionChanged(width: 200, height: 100))
        #expect(reducer.phase == .selecting)
        reducer.handle(.drawBegan)
        #expect(reducer.phase == .editing, "ST-001 行 9：有选区 + 落笔 = editing")
        reducer.handle(.elementCountChanged(1))
        reducer.handle(.drawEnded)
        #expect(reducer.phase == .selecting, "ST-001 行 10：抬手回到 selecting")
        #expect(reducer.hasElements)
    }

    // MARK: - 文案单源

    @Test("提示文案只有一个家：分发器说的就是 MSSessionCopy 那条")
    func dispatcherUsesTheSingleCopy() {
        var reducer = MSSessionReducer()
        reducer.handle(.hotKeyPressed(.snip))
        reducer.handle(.overlayShown)
        reducer.handle(.elementCountChanged(2))
        let effects = reducer.handle(.selectionChanged(width: 100, height: 80))
        #expect(effects.contains(.warnClearAnnotations))
        // 文案不许暗示可撤销：清空同时重置了历史
        #expect(!MSSessionCopy.annotationCleared.contains("撤销") || MSSessionCopy.annotationCleared.contains("无法撤销"),
                "文案必须说实话：清空不可撤销")
    }

    // MARK: - 视图侧的真实顺序（这条最容易写反）

    @MainActor
    private func makeWindow() -> (MSOverlayWindow, Spy) {
        let ctx = CGContext(data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 250))
        let window = MSOverlayWindow(display: MSTestCard.display, frame: ctx.makeImage()!)
        let spy = Spy()
        spy.watched = window.overlayView
        window.overlayDelegate = spy
        window.overlayView.setSelection(CGRect(x: 20, y: 20, width: 200, height: 140))
        window.overlayView.tool = .rect
        return (window, spy)
    }

    @MainActor
    @Test("画一件后改选区尺寸：通知到达时元素还在（顺序对了提示才会响）")
    func notificationArrivesBeforeTheClear() throws {
        let (window, spy) = makeWindow()
        let view = window.overlayView
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 60, y: 140)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 150, y: 80)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 150, y: 80)))
        #expect(view.document?.elements.count == 1, "先真的画出一件")
        #expect(spy.elementCounts.last == 1, "元素数必须报给会话，got=\(spy.elementCounts)")
        #expect(spy.phases.contains { if case .began = $0 { true } else { false } }, "落笔要报 began（行 9 的生产者）")

        spy.selectionNotifications.removeAll()
        spy.elementCountAtNotification.removeAll()
        view.setSelection(CGRect(x: 20, y: 20, width: 120, height: 90))     // 改尺寸
        let countWhenNotified = try #require(spy.elementCountAtNotification.first)
        #expect(countWhenNotified == 1, "通知会话那一刻元素必须还在，否则行 7 永远不提示（got \(countWhenNotified)）")
        #expect(view.document?.elements.isEmpty == true, "通知之后才真的清空")
        #expect(spy.elementCounts.last == 0, "清空也要报数，hasElements 才不会说谎")
    }

    @MainActor
    @Test("首次定选区（没有上一尺寸）不提示")
    func firstSelectionDoesNotWarn() {
        let ctx = CGContext(data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 250))
        let window = MSOverlayWindow(display: MSTestCard.display, frame: ctx.makeImage()!)
        let spy = Spy()
        spy.watched = window.overlayView
        window.overlayDelegate = spy
        window.overlayView.setSelection(CGRect(x: 20, y: 20, width: 200, height: 140))
        #expect(spy.selectionNotifications.count == 1, "第一次定选区只通知一次")
    }

    /// 端到端那一环（`Effect → 分发器 → onToast`）现在能测了：会话带一个"创建但不呈现"
    /// 的测试入口（`B-029` 11-17 裁决），所以判据跑完屏幕上**不会**出现遮罩。
    @MainActor
    @Test("改选区清空后 onToast 真收到那句文案，且全程没有呈现遮罩")
    func coordinatorToastsWithoutPresenting() async throws {
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(),
                                         preferences: MSFakePreferences(),
                                         pins: MSPinRegistry(),
                                         clipboard: MSClipboardWriter(pasteboard: MSFakePasteboard()))
        coord.presentsOverlay = false
        var toasts: [String] = []
        coord.onToast = { toasts.append($0) }
        coord.handle(.snip)
        for _ in 0..<40 where !coord.overlayVisible { try await Task.sleep(for: .milliseconds(25)) }
        let window = try #require(coord.overlay, "遮罩窗应已创建")
        #expect(!window.isVisible, "测试不许劫持屏幕：窗必须没呈现")

        coord.overlay(window, elementCount: 2)
        coord.overlay(window, selectionDidChange: CGRect(x: 0, y: 0, width: 120, height: 90))
        #expect(toasts == [MSSessionCopy.annotationCleared], "got=\(toasts)")
        // 回归护栏：会话中途的选区变化**不许**把遮罩关掉（11-17 我就写错过一次，
        // 症状是 probe-freeze 里 visible=false + 日志刷 illegal migration effectsFinished）
        #expect(coord.overlayVisible, "选区变化之后遮罩必须还在（finishEffects 误用的回归护栏）")

        toasts.removeAll()
        coord.overlay(window, elementCount: 0)
        coord.overlay(window, selectionDidChange: CGRect(x: 0, y: 0, width: 90, height: 60))
        #expect(toasts.isEmpty, "空清空不该弹提示，got=\(toasts)")
        #expect(!window.isVisible, "跑完仍然没呈现过")
    }

    @MainActor

    // 端到端那一环（Effect → 分发器 → `onToast` → 屏上真出条）**没有**在这里测：
    // 要走通它必须让会话真的开遮罩，那会在开发者屏幕上弹一个全屏窗并留到进程退出——
    // 测试不该劫持人的屏幕。这条留作未验项（`B-029`），当前只由"分发器必须穷举"的门禁结构性兜住。

    private func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: type,
                         mouseCursorPosition: CGPoint(x: p.x, y: realHeight - p.y), mouseButton: .left)!
        return NSEvent(cgEvent: cg)!
    }
}
