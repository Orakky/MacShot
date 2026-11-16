import AppKit
import CoreGraphics
import MSCore
import MSTestSupport
import Testing
@testable import MSOverlay

/// 纯几何单测看不见视图自己做的坐标换算，所以这里**离屏渲染一次**去量"✕ 到底画在哪"。
/// 11-16 实拍发现：命中区在左上（单测全绿），而画出来的 ✕ 落在左下 —— 视图里多翻了一次 y，
/// 等于鼠标那条退出路径指向了一个空白处。
struct OverlayPaintTests {
    private var display: MSDisplay { MSTestCard.display }

    /// 均匀底图：这样"有没有被画过东西"就等于"这块区域还均不均匀"。
    private func flatFrame(_ size: CGSize) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(180, 180, 180).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        return ctx.makeImage()!
    }

    private func render() throws -> NSBitmapImageRep {
        let view = MSOverlayView(display: display, frozenFrame: flatFrame(display.logicalFrame.size))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds), "离屏渲染拿到位图")
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 区域内与"该区域中位亮度"不同的像素占比：0 ⇒ 这块什么都没画。
    /// 入参是**视图坐标（y 向上）**，`NSBitmapImageRep.colorAt` 的行号是**图像坐标（y 向下）**，
    /// 这里必须显式换算一次——上一版这行测试直接把视图 y 当行号用，量反了方向。
    private func paintedFraction(_ rep: NSBitmapImageRep, viewRect: CGRect, viewHeight: CGFloat, scale: CGFloat) -> Double {
        let top = (viewHeight - viewRect.maxY) * scale
        let box = MSIntRect(x: Int(viewRect.minX * scale), y: Int(top),
                            width: max(1, Int(viewRect.width * scale)), height: max(1, Int(viewRect.height * scale)))
        var lum: [Double] = []
        for y in box.minY..<min(box.maxY, rep.pixelsHigh) {
            for x in box.minX..<min(box.maxX, rep.pixelsWide) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                lum.append(0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
            }
        }
        guard lum.count > 8 else { return -1 }
        let mid = lum.sorted()[lum.count / 2]
        let off = lum.filter { abs($0 - mid) > 0.06 }
        return Double(off.count) / Double(lum.count)
    }

    /// 区域内平均亮度（同样按图像行号换算视图 y）。
    private func meanLuminance(_ rep: NSBitmapImageRep, viewRect: CGRect, viewHeight: CGFloat, scale: CGFloat) -> Double {
        let box = MSIntRect(x: Int(viewRect.minX * scale), y: Int((viewHeight - viewRect.maxY) * scale),
                            width: max(1, Int(viewRect.width * scale)), height: max(1, Int(viewRect.height * scale)))
        var sum = 0.0, n = 0
        for y in box.minY..<min(box.maxY, rep.pixelsHigh) {
            for x in box.minX..<min(box.maxX, rep.pixelsWide) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                sum += 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent; n += 1
            }
        }
        return n == 0 ? -1 : sum / Double(n)
    }

    @Test("画出来的 ✕ 就在命中区里（视图不许自己换算坐标）")
    func cancelGlyphPaintsInsideItsHitRect() throws {
        let rep = try render()
        let scale = CGFloat(rep.pixelsWide) / display.logicalFrame.width
        let bounds = CGRect(origin: .zero, size: display.logicalFrame.size)
        let hit = OverlayChrome.cancelHitRect(in: bounds)
        let mirror = CGRect(x: hit.minX, y: bounds.minY + OverlayChrome.margin,
                            width: hit.width, height: hit.height)   // 视图左下：多翻一次 y 就会画到这里

        func fraction(_ rect: CGRect) -> Double {
            paintedFraction(rep, viewRect: rect, viewHeight: bounds.height, scale: scale)
        }
        let top = fraction(hit)
        let bottom = fraction(mirror)
        #expect(top > 0.08, "命中区里应能看到 ✕（实测占比 \(top)）")
        #expect(bottom < 0.02, "左下镜像区应保持干净（实测占比 \(bottom)）")
    }

    @Test("命中区与绘制区是同一个矩形")
    func paintRectEqualsHitAreaSpace() {
        let bounds = CGRect(origin: .zero, size: display.logicalFrame.size)
        let paint = OverlayChrome.cancelPaintRect(in: bounds)
        let hit = OverlayChrome.cancelHitRect(in: bounds)
        #expect(hit.contains(paint), "画出去的东西必须整个落在点得到的范围内")
        #expect(paint.midY > bounds.midY, "y 向上：✕ 属于屏幕上方那一侧")
    }

    @Test("暗化层只认 design-system 的两个 token 值，不许自造")
    func scrimAlphaIsTheToken() {
        #expect(OverlayChrome.scrimAlpha(isDark: false) == 0.45)
        #expect(OverlayChrome.scrimAlpha(isDark: true) == 0.55)
    }

    /// 渲染出来的像素必须真的等于 token：180 灰底 ×(1−alpha)。
    /// 旧实现自造 0.35/0.45，量出来是 0.459 —— 不在两个合法值里，这条会直接红。
    @Test("离屏渲染的暗化量落在 token 之内")
    func renderedScrimMatchesToken() throws {
        let rep = try render()
        let scale = CGFloat(rep.pixelsWide) / display.logicalFrame.width
        let bounds = CGRect(origin: .zero, size: display.logicalFrame.size)
        let quiet = CGRect(x: bounds.width * 0.4, y: bounds.midY - 20, width: 40, height: 40)
        let mean = meanLuminance(rep, viewRect: quiet, viewHeight: bounds.height, scale: scale)
        let expected = [0.45, 0.55].map { (180.0 / 255.0) * (1 - $0) }
        let closest = expected.map { abs(mean - $0) }.min() ?? 1
        #expect(closest < 0.03, "实测 \(String(format: "%.3f", mean)) 应接近 0.45/0.55 两档之一")
    }
}
