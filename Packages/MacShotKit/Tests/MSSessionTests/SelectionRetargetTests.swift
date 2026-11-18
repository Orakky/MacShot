import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import MSSettings
import Testing
@testable import MSOverlay
@testable import MSSession

/// 用户 11-18 报的第 2 条：**标注之后一改选区，标注全没了**。
/// 旧档（`Q-11` 临时默认）就是"改选区＝全清 + 不可撤销"，用户明确改判成：
/// **屏幕位置还在新选区里的标注原地保留，跑到外面的才清掉**。
/// 判据一律量"屏幕位置"，不量内部坐标——坐标对了但落在别处，用户看到的还是"标注跑了"。
struct SelectionRetargetTests {
    private static let display = MSTestCard.display      // 400×250 逻辑点，scale 2

    @MainActor
    private final class Spy: MSOverlayDelegate {
        var drops: [Int] = []
        var elementCounts: [Int] = []
        func overlay(_ overlay: MSOverlayWindow, didDropAnnotations count: Int) { drops.append(count) }
        func overlay(_ overlay: MSOverlayWindow, elementCount: Int) { elementCounts.append(elementCount) }
        func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {}
        func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) {}
        func overlayDidCancel(_ overlay: MSOverlayWindow) {}
        func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase) {}
        func overlay(_ overlay: MSOverlayWindow, didPickColor text: String) {}
        func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage? { nil }
        func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences { .init() }
    }

    @MainActor
    private func makeView() -> (MSOverlayView, MSOverlayWindow, Spy) {
        let ctx = CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let window = MSOverlayWindow(display: Self.display, frame: ctx.makeImage()!)
        let spy = Spy()
        window.overlayDelegate = spy
        let view = window.overlayView
        view.setSelection(CGRect(x: 20, y: 20, width: 200, height: 140))
        view.tool = .rect
        return (view, window, spy)
    }

    @MainActor
    private func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let realH = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: type,
                         mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
        return NSEvent(cgEvent: cg)!
    }

    /// 真事件画一个矩形，返回它在**视图坐标**里的外接框（屏幕位置）。
    @MainActor
    private func drawRect(_ view: MSOverlayView, from: CGPoint, to: CGPoint) throws -> CGRect {
        let before = view.document?.elements.count ?? 0
        view.mouseDown(with: mouse(.leftMouseDown, from))
        view.mouseDragged(with: mouse(.leftMouseDragged, to))
        view.mouseUp(with: mouse(.leftMouseUp, to))
        let elements = view.document?.elements ?? []
        #expect(elements.count == before + 1, "一笔都没画出来，这条判据就是空的")
        let e = try #require(elements.last)
        let sel = try #require(view.selection)
        let box = try #require(MSAnnotationGeometry.bounds(of: e))
        return CGRect(x: box.cgRect.minX / Self.display.scale + sel.minX,
                      y: sel.maxY - box.cgRect.maxY / Self.display.scale,
                      width: box.cgRect.width / Self.display.scale,
                      height: box.cgRect.height / Self.display.scale)
    }

    @MainActor
    @Test("改选区位置后标注留在屏幕原地：外接框在视图坐标里一分不差")
    func movingTheSelectionKeepsElementsOnScreen() throws {
        let (view, _, _) = makeView()
        let onScreen = try drawRect(view, from: CGPoint(x: 60, y: 130), to: CGPoint(x: 160, y: 60))

        view.setSelection(CGRect(x: 60, y: 50, width: 200, height: 140))     // 同尺寸，往右上平移
        let sel = try #require(view.selection)
        let e = try #require(view.document?.elements.last)
        let box = try #require(MSAnnotationGeometry.bounds(of: e))
        let after = CGRect(x: box.cgRect.minX / Self.display.scale + sel.minX,
                           y: sel.maxY - box.cgRect.maxY / Self.display.scale,
                           width: box.cgRect.width / Self.display.scale,
                           height: box.cgRect.height / Self.display.scale)
        #expect(abs(after.minX - onScreen.minX) < 0.6 && abs(after.minY - onScreen.minY) < 0.6
                && abs(after.width - onScreen.width) < 0.6 && abs(after.height - onScreen.height) < 0.6,
                "选区平移后标注在屏幕上跑了：\(onScreen) → \(after)")
    }

    @MainActor
    @Test("缩选区：跑到外面的才清掉，报的条数与真丢的一致")
    func shrinkingDropsOnlyWhatFallsOutside() throws {
        let (view, _, spy) = makeView()
        _ = try drawRect(view, from: CGPoint(x: 60, y: 130), to: CGPoint(x: 160, y: 60))    // 靠左上，缩掉后会跑到外面
        _ = try drawRect(view, from: CGPoint(x: 30, y: 150), to: CGPoint(x: 55, y: 135))    // 紧贴左上角，仍在范围内
        let before = view.document?.elements.count ?? 0
        #expect(before == 2, "前置：得有两件，位置一远一近，got=\(before)")

        view.setSelection(CGRect(x: 120, y: 20, width: 90, height: 60))      // 整块挪到右下
        let left = view.document?.elements ?? []
        #expect(left.count < before, "选区整块挪走后一件都没丢 ⇒ 平移量算错了")
        #expect(spy.drops == [before - left.count], "提示条数与实际丢失不符：drops=\(spy.drops) left=\(left.count)")
    }

    @MainActor
    @Test("这是一条可撤销记录：⌘Z 一次把丢掉的标注连同位置一起还回来")
    func oneUndoRestoresEverything() throws {
        let (view, _, spy) = makeView()
        _ = try drawRect(view, from: CGPoint(x: 60, y: 130), to: CGPoint(x: 160, y: 60))
        _ = try drawRect(view, from: CGPoint(x: 30, y: 150), to: CGPoint(x: 55, y: 135))
        let original = view.document?.elements ?? []
        #expect(original.count == 2)

        view.setSelection(CGRect(x: 120, y: 20, width: 90, height: 60))
        let droppedCount = view.document?.elements.count ?? -1
        #expect(droppedCount < 2 && !spy.drops.isEmpty, "没真丢东西，撤销判据就是空的")

        var doc = view.document
        let undone = view.history.undo(&doc!)
        #expect(undone, "改选区必须可撤销（旧档写的'无法撤销'已被用户改判）")
        view.document = doc
        #expect(doc?.elements.count == 2, "撤销后条数没回来，got=\(doc?.elements.count ?? -1)")
        #expect(Set(doc?.elements.map(\.id) ?? []) == Set(original.map(\.id)), "回来的必须是原来那两件")
        #expect(doc?.elements.map(\.points) == original.map(\.points),
                "撤销要连**位置**一起回到改动前，不然标注会停在平移后的地方")
    }

    @MainActor
    @Test("没丢东西就不许提示（范围内原地保留是常态，不是异常）")
    func noDropNoWarning() throws {
        let (view, _, spy) = makeView()
        _ = try drawRect(view, from: CGPoint(x: 60, y: 130), to: CGPoint(x: 160, y: 60))
        view.setSelection(CGRect(x: 20, y: 20, width: 200, height: 160))     // 只往外扩，元素全在里面
        #expect(spy.drops.isEmpty, "一条都没丢却报了数：\(spy.drops)")
        #expect((view.document?.elements.count ?? 0) == 1)
    }
}
