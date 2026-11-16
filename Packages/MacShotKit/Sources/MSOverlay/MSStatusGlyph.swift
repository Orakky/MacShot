import AppKit

/// 菜单栏图形（UI-006）。真源是 `assets/branding/macshot-menubar-template.svg`，运行时直接当资源用——
/// 实测 AppKit 能把 SVG 读成可缩放的矢量 `NSImage`，所以不做光栅化副本，也就不存在第二份要同步的图形。
///
/// 读不到素材时返回 `nil` 而不是崩：图形坏掉不该让"左键直接截图"这个入口消失（FR-HOT-013），
/// 调用方据此回落文字 ✂。
public enum MSStatusGlyph {
    public static let resourceName = "macshot-menubar-template"
    /// macOS 状态栏可视高约 22pt，取 18pt 留呼吸；图形本身是模板图，深浅菜单栏由系统着色。
    public static let pointSize: CGFloat = 18

    public static func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "svg")
    }

    public static func image(in bundle: Bundle = .main) -> NSImage? {
        guard let url = url(in: bundle), let image = NSImage(contentsOf: url),
              !image.representations.isEmpty else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// 画进位图后的落墨比例（0…1）。用来把"素材能加载"和"素材真画得出东西"分开证——
    /// 空白的模板图在系统菜单栏里就是"图标不见了"，而这一步只能量出来。
    public static func inkCoverage(of image: NSImage, side: CGFloat = 36) -> Double {
        let canvas = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        guard let tiff = canvas.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return 0 }
        var ink = 0, probed = 0
        for y in stride(from: 0, to: bmp.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bmp.pixelsWide, by: 2) {
                probed += 1
                if let c = bmp.colorAt(x: x, y: y), c.alphaComponent > 0.2 { ink += 1 }
            }
        }
        return probed == 0 ? 0 : Double(ink) / Double(probed)
    }
}
