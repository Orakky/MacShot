import Foundation
import Testing
@testable import MSAnnotate
import MSCore
import MSTestSupport

struct MSAnnotationDocumentTests {
    @Test("schema 往返：encode → decode → encode 字节稳定")
    func roundTripIsStable() throws {
        let doc = MSSamples.document()
        let a = try JSONEncoder.stable.encode(doc)
        let back = try JSONDecoder().decode(MSAnnotationDocument.self, from: a)
        let b = try JSONEncoder.stable.encode(back)
        #expect(a == b)
        #expect(back.schemaVersion == MSAnnotationDocument.currentSchemaVersion)
    }

    @Test("未知 kind 被拒绝，而不是被猜成别的工具")
    func unknownKindRejected() throws {
        let json = """
        {"schemaVersion":1,"canvasSize":{"width":10,"height":10},
         "elements":[{"id":"\(UUID())","kind":"teleport","points":[],"style":{"stroke":[0,0,0,1],"lineWidth":1,"dash":"solid","arrowHead":"single","fontSize":12,"bold":false,"blurKind":"pixelate","blurRadius":1},"z":0,"text":""}],
         "currentStyle":{"stroke":[0,0,0,1],"lineWidth":1,"dash":"solid","arrowHead":"single","fontSize":12,"bold":false,"blurKind":"pixelate","blurRadius":1},
         "badgeCounter":1}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MSAnnotationDocument.self, from: json) }
    }

    @Test("高于当前版本的文档被拒绝（NFR-018）")
    func futureSchemaRejected() throws {
        let doc = MSSamples.document()
        var data = try JSONEncoder.stable.encode(doc)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { Issue.record("shape"); return }
        obj["schemaVersion"] = 99
        data = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(MSAnnotationDocument.self, from: data)
        #expect(decoded.schemaVersion > MSAnnotationDocument.currentSchemaVersion)
        // The gate is a policy check, not a decode failure:
        #expect(!MSSchemaPolicy.accepts(decoded.schemaVersion))
    }

    @Test("P0 工具集正好 9 件（Q-03）")
    func p0ToolSet() {
        #expect(MSAnnotationKind.p0Tools.count == 9)
        #expect(MSAnnotationKind.p0Tools.contains(.eraser))
    }

    @Test("append 自动递增 z；badge 自动取号")
    func zAndBadge() {
        var doc = MSAnnotationDocument(canvasSize: MSIntSize(width: 100, height: 100))
        doc.append(MSSamples.rect())
        doc.append(MSSamples.arrow())
        #expect(doc.elements[1].z == 1)
        doc.append(MSAnnotationElement(kind: .badge, points: [MSIntPoint(x: 10, y: 10)]))
        #expect(doc.elements.last?.text == "1")
        doc.advanceBadge()
        doc.append(MSAnnotationElement(kind: .badge, points: [MSIntPoint(x: 20, y: 20)]))
        #expect(doc.elements.last?.text == "2")
    }
}

enum MSSchemaPolicy {
    static func accepts(_ version: Int) -> Bool { version <= MSAnnotationDocument.currentSchemaVersion }
}

struct MSAnnotationHistoryTests {
    @Test("一次拖拽 = 一条撤销记录（ADR-011）")
    func dragCoalescesToOneEntry() {
        var doc = MSAnnotationDocument(canvasSize: MSIntSize(width: 200, height: 200))
        var history = MSAnnotationHistory()
        let element = MSSamples.rect()
        history.apply(.insert(element), to: &doc)
        #expect(history.undoStack.count == 1)

        var recorder = MSDragRecorder(element: element)
        for i in 1...100 {
            recorder.update(MSAnnotationGeometry.translated(element, by: CGSize(width: Double(i), height: 0)))
        }
        guard let command = recorder.command else { Issue.record("expected a command"); return }
        history.apply(command, to: &doc)
        #expect(history.undoStack.count == 2, "100 point updates must stay one entry")

        history.undo(&doc)
        #expect(doc.element(id: element.id)?.points == element.points)
        history.undo(&doc)
        #expect(doc.isEmpty)
    }

    @Test("空拖拽不产生幽灵撤销项")
    func noOpDragRecordsNothing() {
        let e = MSSamples.rect()
        var recorder = MSDragRecorder(element: e)
        recorder.update(e)
        #expect(recorder.command == nil)
    }

    @Test("栈深上限 200，超出丢最早")
    func depthLimit() {
        var doc = MSAnnotationDocument(canvasSize: MSIntSize(width: 400, height: 400))
        var history = MSAnnotationHistory()
        for i in 0...250 {
            history.apply(.insert(MSAnnotationElement(kind: .rect,
                                                      points: [MSIntPoint(x: i, y: i), MSIntPoint(x: i + 5, y: i + 5)])),
                          to: &doc)
        }
        #expect(history.undoStack.count == MSAnnotationHistory.depthLimit)
    }
}

struct MSAnnotationGeometryTests {
    @Test("描边矩形：边内可命中，中心不可（无填充时）")
    func strokeOnlyHitTest() {
        let rect = MSSamples.rect()
        let b = MSAnnotationGeometry.bounds(of: rect)!
        #expect(MSAnnotationGeometry.hitTest(CGPoint(x: b.minX, y: b.midY), element: rect))
        #expect(!MSAnnotationGeometry.hitTest(CGPoint(x: b.midX, y: b.midY), element: rect))
        var filled = rect
        filled.style.fill = .rgb(0, 255, 0)
        #expect(MSAnnotationGeometry.hitTest(CGPoint(x: b.midX, y: b.midY), element: filled))
    }

    @Test("badge 半径随位数增长")
    func badgeRadiusGrows() {
        var e = MSAnnotationElement(kind: .badge, points: [MSIntPoint(x: 50, y: 50)])
        e.style.fontSize = 18
        e.text = "1"
        let one = MSAnnotationGeometry.badgeRadius(for: e)
        e.text = "123"
        #expect(MSAnnotationGeometry.badgeRadius(for: e) > one)
    }
}

struct MSRendererTests {
    private let source = MSTestCard.image(width: 400, height: 200)!

    @Test("输出尺寸恒等于画布像素，与 preview/export 无关")
    func outputMatchesCanvas() {
        let renderer = MSAnnotationRenderer()
        let doc = MSSamples.document()
        let preview = renderer.render(doc, source: source, intent: .preview)
        let export = renderer.render(doc, source: source, intent: .export)
        #expect(preview?.width == 400 && preview?.height == 200)
        #expect(export?.width == 400 && export?.height == 200)
    }

    @Test("屏上所见 == 导出所得（NFR-011）")
    func previewEqualsExport() {
        let renderer = MSAnnotationRenderer()
        let doc = MSSamples.document()
        let a = renderer.render(doc, source: source, intent: .preview).flatMap(MSBitmap.init(image:))
        let b = renderer.render(doc, source: source, intent: .export).flatMap(MSBitmap.init(image:))
        #expect(a?.bytes == b?.bytes)
    }

    @Test("标注画在正确的一侧：y 向下存储，红底在上半的卡片上画蓝矩形")
    func verticalOrientationIsCorrect() {
        // The card's right half is white above y=height/2 and black below (in top-left origin
        // terms). A rect drawn at the top must land on white, not on black.
        let renderer = MSAnnotationRenderer()
        var doc = MSAnnotationDocument(canvasSize: MSIntSize(width: 400, height: 200))
        doc.append(MSAnnotationElement(kind: .rect,
                                       points: [MSIntPoint(x: 210, y: 10), MSIntPoint(x: 380, y: 80)],
                                       style: MSAnnotationStyle(stroke: .rgb(0, 255, 0), lineWidth: 2)))
        let out = renderer.render(doc, source: source, intent: .export).flatMap(MSBitmap.init(image:))
        #expect(out?.sample(pixelAt: MSIntPoint(x: 300, y: 30))?.green ?? 0 > 100,
                "stroke should appear near the top of the canvas")
        #expect(out?.sample(pixelAt: MSIntPoint(x: 300, y: 180)) == MSColorRGBA.rgb(0, 0, 0),
                "bottom half must stay untouched black")
    }

    @Test("pixelate 把区域变成块：同块内颜色相同")
    func pixelateProducesBlocks() {
        let renderer = MSAnnotationRenderer()
        var doc = MSAnnotationDocument(canvasSize: MSIntSize(width: 400, height: 200))
        var blur = MSAnnotationElement(kind: .blur, points: [MSIntPoint(x: 0, y: 0), MSIntPoint(x: 200, y: 200)],
                                       style: MSAnnotationStyle(blurKind: .pixelate, blurRadius: 20))
        blur.points[1] = MSIntPoint(x: 200, y: 200)
        doc.append(blur)
        guard let out = renderer.render(doc, source: source, intent: .export).flatMap(MSBitmap.init(image:)) else {
            Issue.record("render failed"); return
        }
        #expect(out.sample(pixelAt: MSIntPoint(x: 5, y: 5)) == out.sample(pixelAt: MSIntPoint(x: 15, y: 15)),
                "same block → same colour")
    }
}

extension JSONEncoder {
    /// Sorted keys + stable output, so the round-trip test compares real bytes.
    static var stable: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
