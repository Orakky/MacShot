import CoreGraphics
import Foundation
import ImageIO
import MSCore
import MSAnnotate
import Testing

/// 渲染基线（`FR-ANN-002` 判据：固定输入 → 与基线 PNG **逐像素一致，容差 0**）。
///
/// 覆盖 8 件几何/像素类工具 × `preview`/`pin`/`export` 三 intent。
/// `text` 与 `badge` **不进字节级基线**：它们画的是系统 UI 字体字形，位图随 macOS 字体版本变，
/// 钉成容差 0 只会造出一台机器上才绿的雷——这两件走结构断言（墨迹包围盒），见下。
///
/// 重新生成：`MACSHOT_SNAPSHOT_UPDATE=1 swift test --filter RendererSnapshotTests`
/// 生成后必须**人眼看一遍**再提交：基线错了就等于把错误固化成判据。
struct RendererSnapshotTests {
    private static let canvas = MSIntSize(width: 120, height: 80)
    private static let intents: [MSRenderIntent] = [.preview, .pin, .export]

    /// 确定性底图：斜向渐变 + 两条实色带。不用随机、不读文件，任何机器输入都一样。
    private static func source() -> CGImage {
        let w = canvas.width, h = canvas.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<h {
            for x in 0..<w {
                let v = Double(x + y) / Double(w + h)
                ctx.setFillColor(MSColorRGBA.rgb(UInt8(40 + 160 * v), UInt8(200 - 120 * v), UInt8(90 + 100 * v)).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        ctx.setFillColor(MSColorRGBA.rgb(255, 255, 255).cgColor)
        ctx.fill(CGRect(x: 0, y: 6, width: w, height: 4))
        ctx.setFillColor(MSColorRGBA.rgb(0, 0, 0).cgColor)
        ctx.fill(CGRect(x: 0, y: 66, width: w, height: 4))
        // 高频细节：4px 棋盘。没有它，"高斯模糊没生效"在平滑渐变上几乎看不出来，
        // 基线就抓不住这类回归（第一次生成时目视就发现了这点）。
        for y in stride(from: 24, to: 56, by: 4) {
            for x in stride(from: 24, to: 96, by: 4) {
                let dark = ((x / 4) + (y / 4)) % 2 == 0
                ctx.setFillColor(MSColorRGBA.rgb(dark ? 15 : 240, dark ? 15 : 240, dark ? 15 : 240).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return ctx.makeImage()!
    }

    private static func doc(_ kind: MSAnnotationKind, _ points: [MSIntPoint], _ style: MSAnnotationStyle,
                            text: String = "", variant: String? = nil) -> MSAnnotationDocument {
        var d = MSAnnotationDocument(canvasSize: canvas)
        d.elements.append(MSAnnotationElement(kind: kind, points: points, style: style, text: text, variant: variant))
        return d
    }

    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MSAnnotateTests/
            .deletingLastPathComponent()          // Tests/
            .appendingPathComponent("Fixtures/baselines")
    }

    private static var isUpdateMode: Bool {
        ProcessInfo.processInfo.environment["MACSHOT_SNAPSHOT_UPDATE"] == "1"
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            Issue.record("PNG 目的建不出来：\(url.lastPathComponent)"); return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { Issue.record("PNG 写入失败：\(url.lastPathComponent)") }
    }

    private static func decodePNG(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func bytes(_ image: CGImage) -> [UInt8] { MSBitmap(image: image)?.bytes ?? [] }

    private static func firstDiff(_ a: [UInt8], _ b: [UInt8]) -> String? {
        guard a.count == b.count else { return "尺寸不同 got=\(a.count) want=\(b.count)" }
        guard let i = a.indices.first(where: { a[$0] != b[$0] }) else { return nil }
        let px = i / 4
        return "第 \(i) 字节（像素 x=\(px % 120), y=\(px / 120)）got=\(a[i]) want=\(b[i])"
    }

    @Test("8 件工具 × 三 intent 与基线逐像素一致（容差 0）")
    func geometryToolsMatchBaselines() throws {
        var red = MSAnnotationStyle.standard
        red.stroke = .rgb(232, 51, 71)
        var filled = red
        filled.fill = .rgba(232, 51, 71, 0.35); filled.cornerRadius = 6; filled.dash = .dash
        var blue = MSAnnotationStyle.standard
        blue.stroke = .rgb(10, 132, 255); blue.lineWidth = 2
        var tri = MSAnnotationStyle.standard
        tri.arrowHead = .triangle
        var hl = MSAnnotationStyle.standard
        hl.stroke = .rgba(255, 204, 0, 0.55); hl.lineWidth = 10
        var pix = MSAnnotationStyle.standard
        pix.blurKind = .pixelate; pix.blurRadius = 8
        var gau = MSAnnotationStyle.standard
        gau.blurKind = .gaussian; gau.blurRadius = 6

        let zig = stride(from: 8, through: 108, by: 7).map { MSIntPoint(x: $0, y: 40 + ($0 / 7 % 2 == 0 ? -14 : 14)) }
        let cases: [(String, MSAnnotationDocument)] = [
            ("rect", Self.doc(.rect, [MSIntPoint(x: 10, y: 10), MSIntPoint(x: 110, y: 70)], red)),
            ("rect-filled", Self.doc(.rect, [MSIntPoint(x: 14, y: 12), MSIntPoint(x: 96, y: 64)], filled)),
            ("ellipse", Self.doc(.ellipse, [MSIntPoint(x: 12, y: 10), MSIntPoint(x: 108, y: 70)], blue)),
            ("arrow", Self.doc(.arrow, [MSIntPoint(x: 12, y: 62), MSIntPoint(x: 104, y: 16)], tri)),
            ("polyline", Self.doc(.polyline, [MSIntPoint(x: 10, y: 60), MSIntPoint(x: 40, y: 20),
                                         MSIntPoint(x: 70, y: 55), MSIntPoint(x: 106, y: 14)], blue)),
            ("freehand-pen", Self.doc(.freehand, zig, red, variant: "pen")),
            ("freehand-highlighter", Self.doc(.freehand, zig, hl)),
            ("blur-pixelate", Self.doc(.blur, [MSIntPoint(x: 20, y: 18), MSIntPoint(x: 100, y: 62)], pix)),
            ("blur-gaussian", Self.doc(.blur, [MSIntPoint(x: 20, y: 18), MSIntPoint(x: 100, y: 62)], gau)),
        ]
        let renderer = MSAnnotationRenderer()
        let src = Self.source()
        try FileManager.default.createDirectory(at: Self.fixturesDir, withIntermediateDirectories: true)

        for (name, document) in cases {
            for intent in Self.intents {
                let url = Self.fixturesDir.appendingPathComponent("\(name)-\(intent.rawValue).png")
                guard let image = renderer.render(document, source: src, intent: intent) else {
                    Issue.record("\(name)/\(intent.rawValue) 渲染返回 nil"); continue
                }
                #expect(MSIntSize(width: image.width, height: image.height) == document.canvasSize,
                        "\(name)/\(intent.rawValue) 输出尺寸不等于画布")
                if Self.isUpdateMode {
                    Self.writePNG(image, to: url)
                    continue
                }
                guard let baseline = Self.decodePNG(url) else {
                    Issue.record("基线缺失：\(url.lastPathComponent)。先跑 MACSHOT_SNAPSHOT_UPDATE=1 生成并人眼确认")
                    continue
                }
                let diff = Self.firstDiff(Self.bytes(image), Self.bytes(baseline))
                #expect(diff == nil, "\(name)/\(intent.rawValue) 与基线不符：\(diff ?? "")")
            }
        }
    }

    /// `text`/`badge` 的字形随系统字体版本走，所以只钉"画没画、画在哪、画了多少墨"，不钉字节。
    /// 能抓住的回归形状：文字跑到别处、墨量归零、颜色整个错。
    @Test("文字与序号走结构断言：墨迹包围盒落在期望位置")
    func textAndBadgeAreStructural() throws {
        let renderer = MSAnnotationRenderer()
        let src = Self.source()
        let empty = MSAnnotationDocument(canvasSize: Self.canvas)
        guard let bare = renderer.render(empty, source: src, intent: .export) else {
            Issue.record("参考图渲染失败"); return
        }
        var style = MSAnnotationStyle.standard
        style.stroke = .rgb(255, 255, 255); style.fontSize = 16

        let cases: [(MSAnnotationDocument, String, MSIntRect)] = [
            (Self.doc(.text, [MSIntPoint(x: 8, y: 12)], style, text: "MacShot"), "text", MSIntRect(x: 8, y: 12, width: 74, height: 22)),
            (Self.doc(.badge, [MSIntPoint(x: 60, y: 40)], style, text: "7"), "badge", MSIntRect(x: 46, y: 26, width: 28, height: 28)),
        ]
        for (document, label, expected) in cases {
            guard let image = renderer.render(document, source: src, intent: .export),
                  let ink = inkBounds(of: image, reference: bare) else {
                Issue.record("\(label) 渲染或墨迹测量失败"); continue
            }
            // 起点必须贴着锚点（字体版本能让宽度差几像素，位置不该差）
            #expect(abs(ink.minX - expected.minX) <= 3 && abs(ink.minY - expected.minY) <= 3,
                    "\(label) 墨迹起点偏了：\(ink) vs 期望 \(expected)")
            #expect(ink.width > 6 && ink.height > 6, "\(label) 墨量过小，等于没画出来：\(ink)")
        }
    }

    /// 每件工具的墨迹必须落在它自己的几何范围内——这条比字节基线更能抓"画到别处去了"，
    /// 而且不受字体版本影响（11-16 文字画不出、序号没数字，字节基线是同一台机器生成的，抓不到）。
    @Test("每件工具的墨迹包围盒与几何一致")
    func everyKindDrawsInkWhereGeometrySays() throws {
        let renderer = MSAnnotationRenderer()
        let src = Self.source()
        guard let bare = renderer.render(MSAnnotationDocument(canvasSize: Self.canvas), source: src, intent: .export) else {
            Issue.record("参考图渲染失败"); return
        }
        var style = MSAnnotationStyle.standard
        style.stroke = .rgb(255, 255, 255)
        var pix = style; pix.blurKind = .pixelate; pix.blurRadius = 8

        let box = MSIntRect(x: 20, y: 18, width: 80, height: 44)
        let cases: [(String, MSAnnotationDocument, MSIntRect)] = [
            ("rect", Self.doc(.rect, [MSIntPoint(x: 20, y: 18), MSIntPoint(x: 100, y: 62)], style), box),
            ("ellipse", Self.doc(.ellipse, [MSIntPoint(x: 20, y: 18), MSIntPoint(x: 100, y: 62)], style), box),
            ("arrow", Self.doc(.arrow, [MSIntPoint(x: 20, y: 62), MSIntPoint(x: 100, y: 18)], style), box),
            ("blur-pixelate", Self.doc(.blur, [MSIntPoint(x: 20, y: 18), MSIntPoint(x: 100, y: 62)], pix), box),
        ]
        for (label, document, expected) in cases {
            guard let image = renderer.render(document, source: src, intent: .export),
                  let ink = inkBounds(of: image, reference: bare) else {
                Issue.record("\(label) 渲染或测量失败"); continue
            }
            // 允许线宽外溢（描边中心线在几何边界上），但不许整块跑到别处
            #expect(ink.minX >= expected.minX - 4 && ink.maxX <= expected.maxX + 4
                    && ink.minY >= expected.minY - 4 && ink.maxY <= expected.maxY + 4,
                    "\(label) 墨迹越出几何框：got=\(ink) want≈\(expected)")
            #expect(ink.width > expected.width / 3, "\(label) 墨迹过少，可能根本没画：\(ink)")
        }
    }

    /// 与"只有底图、零元素"的同尺寸渲染逐像素比差，取差异像素的包围盒。
    /// 两图只差这一个元素，所以差异像素就是它的墨迹——不需要再开窗口去猜位置。
    /// 渲染输出恒为全不透明，所以不能拿 alpha 当尺，只能跟参考图比。
    private func inkBounds(of image: CGImage, reference: CGImage) -> MSIntRect? {
        guard let got = MSBitmap(image: image), let base = MSBitmap(image: reference),
              got.width == base.width, got.height == base.height else { return nil }
        var minX = got.width, minY = got.height, maxX = -1, maxY = -1
        for y in 0..<got.height {
            for x in 0..<got.width {
                let i = y * got.bytesPerRow + x * 4
                if got.bytes[i] != base.bytes[i] || got.bytes[i + 1] != base.bytes[i + 1]
                    || got.bytes[i + 2] != base.bytes[i + 2] || got.bytes[i + 3] != base.bytes[i + 3] {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return MSIntRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
