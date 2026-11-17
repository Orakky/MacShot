import AppKit
import CoreGraphics
import MSCore
import Testing
import MSAnnotate
@testable import MSOverlay

/// `T-094` / `design-system.md` §5（判据住在 `MSOverlayTests`：符号只能经 AppKit 取，
/// 而 `check-deps` 不许 `MSAnnotate` import AppKit ⇒ 事实表在 `MSAnnotationIconTable`，装载器在 `MSOverlayIcons`）。
///图标是**看得见**的承诺，所以判据只有两条路——
/// 要么真画出墨，要么老实回落字母。「格子在、里面空」是最坏的结果，它看起来像功能还在。
struct IconResolutionTests {
    @MainActor
    @Test("每个工具都取得到图标：符号名来自 §5 核对表，折线箭头走自绘")
    func everyToolResolves() {
        for tool in MSTool.allCases {
            if tool == .polyline {
                #expect(MSAnnotationIconTable.symbolName(for: tool) == nil,
                        "折线箭头按 §5 就是没有符号（path.forward / curve 实测都不存在），必须自绘")
            } else {
                #expect(MSAnnotationIconTable.symbolName(for: tool) != nil)
            }
            #expect(MSOverlayIcons.mask(for: tool, side: 16) != nil, "\(tool) 取不到图 ⇒ 只能回落字母")
        }
    }

    @MainActor
    @Test("未知符号名返回 nil，而不是一个空图")
    func unknownSymbolIsNilNotBlank() {
        #expect(MSOverlayIcons.mask(symbolName: "this.symbol.should.not.exist.anywhere") == nil,
                "回落路径的前提是「取不到 = nil」；要是返回了空图，调用方就再也画不出字母了")
    }

    @MainActor
    @Test("每个图标真的有墨：16pt 格子里非透明像素必须成量")
    func everyIconHasInk() throws {
        for tool in MSTool.allCases {
            guard MSOverlayIcons.mask(for: tool, side: 16) != nil else {
                Issue.record("\(tool) 取不到蒙版"); continue
            }
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0))
            let ctx = try #require(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            let drew = MSOverlayIcons.draw(tool, in: CGRect(x: 0, y: 0, width: 16, height: 16),
                                            tint: .labelColor, side: 16)
            NSGraphicsContext.restoreGraphicsState()
            #expect(drew, "\(tool) 的 draw 返回 false ⇒ 会回落字母，图标路径等于没上")
            var ink = 0
            for y in 0..<16 {
                for x in 0..<16 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.35 { ink += 1 }
            }
            // 16×16 = 256 个采样点：少于 14 个像素的东西肉眼基本看不见，等于空白。
            #expect(ink >= 14, "\(tool) 只画出 \(ink) 个像素 ⇒ 太接近空白，格子会看起来是空的")
        }
    }
}
