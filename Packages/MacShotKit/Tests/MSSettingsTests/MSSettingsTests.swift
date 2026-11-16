import CoreGraphics
import Foundation
import Testing
@testable import MSSettings
import MSExport
import MSCore
import MSAnnotate
import MSTestSupport

struct MSDefaultPreferencesTests {
    @Test("默认值与文档表格逐字段相等（FR-SET-003）")
    func defaultsMatchDocumentation() {
        let p = MSAppPreferences()
        #expect(p.schemaVersion == 1)
        #expect(p.hotKeys.snip == .f1, "F1 — keymap.md §1")
        #expect(p.hotKeys.pinClipboard == .f3, "F3")
        #expect(p.hotKeys.fullScreen == MSKeyCombo(keyCode: 0, command: true), "⌘A")
        #expect(p.hotKeys.snip.display == "F1" && p.hotKeys.pinClipboard.display == "F3",
                "回归：曾经把 keyCode 当 F 序号传，F1 静默注册成 A 键")
        #expect(p.commitBehavior == .pin, "Q-05 temporary default: pin first")
        #expect(p.export.directory == "~/Pictures/MacShot")
        #expect(p.export.namingTemplate == "MacShot {yyyy}-{MM}-{dd} {HH}.{mm}.{ss}")
        #expect(p.export.format == .png)
        #expect(p.export.writesPngAndTiffToPasteboard == true, "ADR-014")
        #expect(p.annotationDefaults.strokeHex == "#E83347", "design-system.md §2.2 slot 1")
        #expect(p.annotationDefaults.lineWidth == 3)
    }

    @Test("未落盘时读默认，落盘后读回一致")
    func persistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macshot-tests-\(UUID().uuidString)")
        let store = MSSettingsStore(directory: dir)
        #expect(store.current.commitBehavior == .pin)
        store.update { $0.commitBehavior = .copy }
        let reopened = MSSettingsStore(directory: dir)
        #expect(reopened.current.commitBehavior == .copy)
        reopened.resetToDefaults()
        #expect(MSSettingsStore(directory: dir).current.commitBehavior == .pin)
        try? FileManager.default.removeItem(at: dir)
    }
}

struct MSNamingTemplateTests {
    private let date: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 16
        c.hour = 10; c.minute = 30; c.second = 45
        return Calendar.current.date(from: c)!
    }()

    @Test("变量展开（export-clipboard.md §4）")
    func expands() {
        let t = MSNamingTemplate("MacShot {yyyy}-{MM}-{dd} {HH}.{mm}.{ss}")
        #expect(t.expand(.init(date: date, pixelSize: MSIntSize(width: 860, height: 500), scale: 2))
                == "MacShot 2026-11-16 10.30.45")
        let t2 = MSNamingTemplate("{tool}-{width}x{height}-{scale}-{index}")
        #expect(t2.expand(.init(date: date, pixelSize: MSIntSize(width: 860, height: 500), scale: 2,
                               displayName: "LG Ultra"), index: 7) == "MacShot-860x500-@2x-007")
    }

    @Test("路径分隔符被剔除，目录名不可注入")
    func sanitizesSeparators() {
        #expect(!MSNamingTemplate("a/b:c").expand(.init(date: date)).contains("/"))
    }
}

struct MSClipboardWriterTests {
    private var image: CGImage { MSTestCard.image(width: 120, height: 80)! }

    @Test("写一次、含 PNG 与 TIFF 两种表示（ADR-014）")
    func writesBothRepresentations() {
        let pb = MSFakePasteboard()
        let ok = MSClipboardWriter(pasteboard: pb).write(image, scale: 2, pngAndTiff: true)
        #expect(ok)
        #expect(pb.writeCount == 1, "one atomic write, no half-filled pasteboard")
        #expect(pb.writtenPNG != nil)
        #expect(pb.writtenTIFF != nil)
    }

    @Test("changeCount 未变时报失败，不静默（overview.md §6）")
    func detectsStolenPasteboard() {
        let pb = MSFakePasteboard()
        pb.acceptsWrites = false
        #expect(!MSClipboardWriter(pasteboard: pb).write(image, scale: 2))
    }

    @Test("DPI 元数据 = 72 × scale（FR-EXP-004 / V-005）")
    func dpiRoundTrip() throws {
        for scale in [1, 2] {
            let png = try #require(MSImageEncoder.png(image, scale: scale))
            #expect(MSImageEncoder.reportedDPI(of: png) == 72 * scale)
            let tiff = try #require(MSImageEncoder.tiff(image, scale: scale))
            #expect(MSImageEncoder.reportedDPI(of: tiff) == 72 * scale)
        }
    }

    @Test("PNG 是无损的：像素与源一致")
    func pngIsLossless() throws {
        let data = try #require(MSImageEncoder.png(image, scale: 2))
        let decoded = try #require(MSImageDecoder.image(from: data))
        #expect(MSBitmap(image: image)?.bytes == MSBitmap(image: decoded)?.bytes)
    }
}

struct MSFileExporterTests {
    private var request: MSExportRequest {
        MSExportRequest(image: MSTestCard.image(width: 100, height: 60)!, scale: 2,
                        naming: MSNamingTemplate("MacShot {yyyy}-{MM}-{dd} {HH}.{mm}.{ss}"),
                        directory: URL(fileURLWithPath: "/tmp/macshot-export"))
    }

    @Test("连续 10 次保存不覆盖（FR-EXP-003）")
    func neverOverwrites() throws {
        let writer = MSFakeFileWriter()
        let exporter = MSFileExporter(writer: writer)
        var paths: Set<String> = []
        for _ in 0..<10 {
            // Same second → the plain name exists → index must advance.
            let outcome = exporter.save(request)
            if case .written(let p, _) = outcome { paths.insert(p) }
            if let last = writer.writes.last { writer.existing.insert(last.url.path) }
        }
        #expect(writer.writes.count == 10)
        #expect(paths.count == 10, "each save must land on a fresh path")
    }

    @Test("写失败返回可展示的错误而不是抛出")
    func surfacesFailures() {
        let writer = MSFakeFileWriter()
        writer.shouldFail = true
        let outcome = MSFileExporter(writer: writer).save(request)
        if case .failed = outcome {} else { Issue.record("expected failure") }
    }
}
