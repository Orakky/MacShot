import AppKit
import Foundation
import Testing
@testable import MSOverlay

/// 菜单栏图形只有两条能成立的状态：真源画得出来，或画不出来时明确缺席。
/// "加载成功但是空白"在系统菜单栏里长得和"图标丢了"一模一样，只能靠量墨覆盖拦住。
struct StatusGlyphTests {
    /// 真源在仓库里（`assets/branding/`），不是构建产物 —— 图形只有一个家。
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MSOverlayTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // MacShotKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // 仓库根
    }

    private func bundle(containing fileName: String?) -> Bundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MSStatusGlyphTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        if let fileName {
            try? FileManager.default.copyItem(at: repoRoot.appendingPathComponent("assets/branding/\(fileName)"),
                                              to: dir.appendingPathComponent("Contents/Resources/\(fileName)"))
        }
        return Bundle(url: dir) ?? Bundle.main
    }

    @Test("真源 SVG 能被 AppKit 当矢量资源用（模板图 + 18pt）")
    func sourceRendersAsTemplate() throws {
        let image = try #require(MSStatusGlyph.image(in: bundle(containing: MSStatusGlyph.resourceName + ".svg")))
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        // 画得出来：18pt 下应有可见笔画，且不是整块实心（实心＝模板图会把菜单栏糊成一块）
        let coverage = MSStatusGlyph.inkCoverage(of: image, side: 36)
        #expect(coverage > 0.05)
        #expect(coverage < 0.85)
    }

    @Test("素材缺席时返回 nil（调用方据此回落 ✂，不是崩）")
    func missingAssetReturnsNil() {
        let empty = bundle(containing: nil)
        #expect(MSStatusGlyph.url(in: empty) == nil)
        #expect(MSStatusGlyph.image(in: empty) == nil)
        #expect(MSStatusGlyph.inkCoverage(of: NSImage(size: NSSize(width: 1, height: 1))) == 0)
    }
}
