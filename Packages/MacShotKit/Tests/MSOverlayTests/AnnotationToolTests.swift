import AppKit
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSOverlay

/// `N` 序号与 `E` 橡皮擦是 P0 九件工具里最后两件"点一下就完成"的动作。
/// 这里盯三件事：号码与插入是**同一条**撤销记录、橡皮擦删的是**最上层**、空点不留撤销记录。
struct AnnotationToolTests {
    @MainActor
    private func makeView() -> MSOverlayView {
        let ctx = CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(200, 200, 200).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        let view = MSOverlayView(display: MSTestCard.display, frozenFrame: ctx.makeImage()!)
        view.document = MSAnnotationDocument(canvasSize: MSIntSize(width: 200, height: 120))
        return view
    }

    @MainActor
    @Test("序号徽章自增，且撤销一条就把号码也退回去")
    func badgeInsertsAndAdvancesAsOneStep() throws {
        let view = makeView()
        view.tool = .badge
        view.performClickAction(at: MSIntPoint(x: 20, y: 20))
        view.performClickAction(at: MSIntPoint(x: 60, y: 40))
        var doc = try #require(view.document)
        #expect(doc.elements.count == 2)
        #expect(doc.elements.map(\.text) == ["1", "2"], "徽章文字＝按下时的计数器")
        #expect(doc.badgeCounter == 3)

        let undoBadge = view.history.undo(&doc)   // inout 不能直接进 #expect 宏（会被当不可变捕获）
        #expect(undoBadge, "insert+counter 必须打包成一条记录")
        #expect(doc.elements.count == 1)
        #expect(doc.badgeCounter == 2, "撤销要把计数器一起退回，否则会出现空号 2")
    }

    @MainActor
    @Test("橡皮擦删最上层元素；点空白不产生撤销记录")
    func eraserRemovesTopmostAndIgnoresMiss() throws {
        let view = makeView()
        var doc = try #require(view.document)
        let bottom = MSAnnotationElement(kind: .rect, points: [MSIntPoint(x: 10, y: 10), MSIntPoint(x: 120, y: 100)], z: 0)
        let top = MSAnnotationElement(kind: .rect, points: [MSIntPoint(x: 40, y: 40), MSIntPoint(x: 90, y: 80)], z: 1)
        view.history.apply(.insert(bottom), to: &doc)
        view.history.apply(.insert(top), to: &doc)
        view.document = doc
        view.tool = .eraser

        // 未填充矩形的命中区是轮廓而不是内部（`MSAnnotationGeometry.hitTest`），所以压左边缘才命中
        view.performClickAction(at: MSIntPoint(x: 40, y: 60))   // 上层矩形的左边，且不在底层矩形的边上
        var after = try #require(view.document)
        #expect(after.elements.count == 1, "重叠处必须删最上面那层")
        #expect(after.elements.first?.z == 0, "留下的应是底层")

        // 点空白不该留下撤销记录：下面这次 undo 必须直接回到"两层都在"。
        // 若空点多压了一条记录，undo 会先弹掉那条空记录，这里就还是 1 层。
        view.performClickAction(at: MSIntPoint(x: 195, y: 115))
        #expect(after.elements.count == 1, "空点不该删东西")
        let undoErase = view.history.undo(&after)
        #expect(undoErase, "橡皮擦删除要能撤销")
        #expect(after.elements.count == 2, "一次 undo 就该回到两层 ⇒ 空点没压记录")
    }

    @MainActor
    @Test("工具字母按 keymap 真源，rect 不再占 R")
    func lettersFollowKeymap() {
        #expect(MSTool.rect.letter == "M", "R 属于键位表 §2 的重复上次区域（P1），不能拿来当矩形")
        #expect(MSTool.badge.letter == "N")
        #expect(MSTool.eraser.letter == "E")
        #expect(Set(MSTool.allCases.map(\.letter)).count == MSTool.allCases.count, "键位不许撞车")
        #expect(MSTool.badge.annotationKind == .badge)
        #expect(MSTool.eraser.annotationKind == .eraser)
        #expect(!MSTool.rect.isClickAction)
        #expect(MSTool.badge.isClickAction && MSTool.eraser.isClickAction)
    }
}
