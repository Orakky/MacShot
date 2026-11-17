import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSSettings
import MSTestSupport
import Testing
@testable import MSOverlay

/// ST-003 的 `文字输入` 子态。
/// 判据一律走真实按键路由（`CGEvent` 合成 `NSEvent` 再喂 `handleKey`）——上午 ✕ 那个教训：
/// 绕开真实入口的测试拦不住真 bug。
struct TextEditingTests {
    private func key(_ code: UInt16, _ flags: CGEventFlags = []) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: true)!
        cg.flags = flags
        return NSEvent(cgEvent: cg)!
    }

    /// 记录 delegate 收到的动作，用来证"Esc 在编辑子态里没把整个会话关掉"。
    @MainActor
    private final class Spy: MSOverlayDelegate {
        var cancelled = 0
        var intents: [MSCommitIntent] = []
        var elementCounts: [Int] = []
        var sawDrawBegan = 0
        func overlay(_ overlay: MSOverlayWindow, selectionDidChange rect: CGRect?) {}
        func overlay(_ overlay: MSOverlayWindow, didRequest intent: MSCommitIntent) { intents.append(intent) }
        func overlayDidCancel(_ overlay: MSOverlayWindow) { cancelled += 1 }
        func overlay(_ overlay: MSOverlayWindow, cropOfViewRect rect: CGRect) -> CGImage? { nil }
        func overlayPreferences(_ overlay: MSOverlayWindow) -> MSAppPreferences { .init() }
        func overlay(_ overlay: MSOverlayWindow, drawingPhaseDidChange phase: MSOverlayDrawingPhase) {
            switch phase {
            case .began: sawDrawBegan += 1
            case .ended(let count): elementCounts.append(count)
            }
        }
        func overlay(_ overlay: MSOverlayWindow, elementCount: Int) { elementCounts.append(elementCount) }
    }

    @MainActor
    private func makeWindow() -> (MSOverlayWindow, Spy) {
        let ctx = CGContext(data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(190, 190, 190).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 250))
        let window = MSOverlayWindow(display: MSTestCard.display, frame: ctx.makeImage()!)
        let view = window.overlayView
        view.document = MSAnnotationDocument(canvasSize: MSIntSize(width: 400, height: 250))
        view.setSelection(CGRect(x: 20, y: 20, width: 300, height: 200))
        let spy = Spy()
        window.overlayDelegate = spy
        return (window, spy)
    }

    @MainActor
    @Test("文字工具：Enter 提交后元素含可读文本，且撤销一条就能收回")
    func commitInsertsTextElement() throws {
        let (window, _) = makeWindow()
        let view = window.overlayView
        view.tool = .text
        view.beginTextEditing(at: MSIntPoint(x: 40, y: 60))
        #expect(view.isEditingText)
        view.editorTextView?.string = "第一行\n第二行更长一点"
        #expect(view.handleKey(key(36)), "Enter 必须被子态吃掉")
        #expect(!view.isEditingText)

        let doc = try #require(view.document)
        #expect(doc.elements.count == 1)
        #expect(doc.elements[0].kind == .text)
        #expect(doc.elements[0].text == "第一行\n第二行更长一点", "FR-ANN-007：提交后 text 可读，不是位图")

        var undone = doc
        let undid = view.history.undo(&undone)   // inout 不能进 #expect 宏
        #expect(undid)
        #expect(undone.elements.isEmpty, "一次 ⌘Z 收回整条文字")
    }

    @MainActor
    @Test("Esc 只放弃输入，不退整个遮罩；且不留撤销记录")
    func escapeLeavesSubStateOnly() throws {
        let (window, spy) = makeWindow()
        let view = window.overlayView
        view.tool = .text
        view.beginTextEditing(at: MSIntPoint(x: 40, y: 60))
        view.editorTextView?.string = "没写完的话"
        #expect(view.handleKey(key(53)), "Esc 被子态吃掉")
        #expect(!view.isEditingText)
        #expect(spy.cancelled == 0, "ST-003：编辑子态里的 Esc 不许关掉会话")

        var doc = try #require(view.document)
        #expect(doc.elements.isEmpty)
        let undoAfterAbort = view.history.undo(&doc)
        #expect(!undoAfterAbort, "放弃输入不该留下可撤销的东西")

        // 对照：不在子态时，同一个键必须退会话
        #expect(view.handleKey(key(53)))
        #expect(spy.cancelled == 1)
    }

    @MainActor
    @Test("⇧Enter 不提交（换行交给 field editor），⌘Enter 提交")
    func shiftEnterDoesNotCommit() throws {
        let (window, _) = makeWindow()
        let view = window.overlayView
        view.tool = .text
        view.beginTextEditing(at: MSIntPoint(x: 10, y: 10))
        #expect(!view.handleKey(key(36, .maskShift)), "⇧Enter 交回 field editor ⇒ handleKey 不消费")
        #expect(view.isEditingText, "⇧Enter 之后还在输入态")
        view.editorTextView?.string = "命令式提交"
        #expect(view.handleKey(key(36, .maskCommand)))
        #expect(!view.isEditingText)
        let committed = try #require(view.document)
        #expect(committed.elements.first?.text == "命令式提交")
    }

    @MainActor
    @Test("空文本提交不入记录")
    func emptyTextLeavesNoRecord() throws {
        let (window, _) = makeWindow()
        let view = window.overlayView
        view.tool = .text
        view.beginTextEditing(at: MSIntPoint(x: 10, y: 10))
        view.editorTextView?.string = "   \n "
        #expect(view.handleKey(key(36)))
        var doc = try #require(view.document)
        #expect(doc.elements.isEmpty)
        let undoEmpty = view.history.undo(&doc)
        #expect(!undoEmpty, "空文本不该产生撤销步骤")
    }

    @MainActor
    @Test("文本行数进 bounds：改文本长度后 bounds 更新正确（FR-ANN-007 判据）")
    func boundsFollowTextShape() throws {
        let (window, _) = makeWindow()
        let view = window.overlayView
        view.tool = .text
        view.beginTextEditing(at: MSIntPoint(x: 0, y: 0))
        view.editorTextView?.string = "ab"
        view.commitTextEditing()
        let docAfterOne = try #require(view.document)
        let one = try #require(docAfterOne.elements.first)
        view.beginTextEditing(at: MSIntPoint(x: 0, y: 0), existing: one)
        view.editorTextView?.string = "ab\ncd\nef"
        view.commitTextEditing()
        let doc = try #require(view.document)
        #expect(doc.elements.count == 1, "再编辑同一元素走 replace，不新增")
        #expect(doc.elements[0].id == one.id, "id 不变（贴图再编辑的判据）")
        let b1 = MSAnnotationGeometry.bounds(of: one), b2 = MSAnnotationGeometry.bounds(of: doc.elements[0])
        #expect(b2!.height > b1!.height, "三行必须比一行高（\(b1!.height) → \(b2!.height)）")
    }

    @Test("编辑器矩形向下长：锚点是文字左上，视图 y 向上")
    func editorFrameGrowsDownward() {
        let selection = CGRect(x: 100, y: 200, width: 400, height: 300)
        let f = MSOverlayView.editorFrame(anchor: MSIntPoint(x: 0, y: 0), selection: selection,
                                          scale: 1, fontSize: 18, lines: 2)
        #expect(abs(f.maxY - selection.maxY) < 0.01, "首行左上角贴在选区上沿（画布 y=0）")
        #expect(f.minY < f.maxY && f.height > 18, "框向下长：\(f)")
        let deeper = MSOverlayView.editorFrame(anchor: MSIntPoint(x: 0, y: 100), selection: selection,
                                               scale: 1, fontSize: 18, lines: 1)
        #expect(deeper.maxY < f.maxY, "画布 y 越大，视图里越靠下")
    }

    @MainActor
    @Test("再按同一工具键＝收回工具（ST-003 工具待落笔）")
    func sameToolKeyTogglesBack() {
        let (window, _) = makeWindow()
        let view = window.overlayView
        #expect(view.handleKey(key(0)), "keyCode 0＝A＝箭头")     // A（17 是 T，别记混）
        #expect(view.tool == .arrow)
        #expect(view.handleKey(key(0)))
        #expect(view.tool == .select, "同一个键再按一次要收回工具")
        #expect(view.handleKey(key(17)))
        #expect(view.tool == .text, "T＝文字（keymap §3）")
    }
}
