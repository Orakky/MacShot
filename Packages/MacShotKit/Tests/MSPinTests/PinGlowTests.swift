import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSPin

/// 用户 11-18 要的"贴出置顶边缘带光晕、悬浮感"。
/// 这里盯的不是好不好看（那要眼睛看，`make probe-pin` 出图），而是三件容易做错的事：
/// ① 光晕**不许吃内容像素**——看到的效果必须与复制出去的是同一张图（`NFR-011`）；
/// ② 光晕要真的画在留白里并且由内向外衰减（画成一条实线边框就等于没做）；
/// ③ 窗、图片、工具带的几何仍然只有一个来源（`imageRect`）。
struct PinGlowTests {
    @MainActor
    private func makePin(width: Int, height: Int) -> (MSPinWindow, MSPinView) {
        let ctx = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(30, 60, 90).cgColor)     // 深蓝灰：任何白色污染都藏不住
        ctx.fill(CGRect(x: 0, y: 0, width: width * 2, height: height * 2))
        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: width * 2, height: height * 2)),
                                   source: ctx.makeImage()!, scale: 2)
        let window = MSPinWindow(content: content, origin: NSPoint(x: 200, y: 200), menu: nil)
        return (window, window.pinView)
    }

    @MainActor
    private func render(_ view: MSPinView) throws -> (NSBitmapImageRep, CGFloat) {
        view.needsDisplay = true
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds), "离屏渲染拿不到位图")
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    @MainActor
    @Test("光晕一个内容像素都不吃：图片区域内每个采样点都还是源色")
    func glowNeverCoversContent() throws {
        let (_, view) = makePin(width: 120, height: 90)
        let (rep, scale) = try render(view)
        let image = view.imageRect
        var contaminated = 0, sampled = 0
        // 从**贴着边界 0.5pt** 开始采：上一版让开了 2pt，结果"1pt 高光压进画面"这种污染正好漏掉，
        // 反证跑下去判据还是绿的——盲区比 bug 更糟。
        for v in stride(from: image.minY + 0.5, to: image.maxY - 0.5, by: 1.5) {
            for u in stride(from: image.minX + 0.5, to: image.maxX - 0.5, by: 1.5) {
                guard let c = rep.colorAt(x: Int(u * scale), y: Int((view.bounds.height - v) * scale)) else { continue }
                sampled += 1
                let b = max(c.redComponent, c.greenComponent, c.blueComponent)
                // 源色 (30,60,90)/255 的最大通道 = 0.353；白色环会把任何一个通道抬上去
                if b > 0.36 || c.alphaComponent < 0.99 { contaminated += 1 }
            }
        }
        #expect(sampled > 800, "采样点太少，这条判据是空的：\(sampled)")
        #expect(contaminated == 0, "图片区域里 \(contaminated)/\(sampled) 个采样点被光晕改了颜色")
    }

    @MainActor
    @Test("留白里有光晕，且由内向外衰减（画成实线边框＝没有衰减）")
    func glowLivesInTheMarginAndFades() throws {
        let (_, view) = makePin(width: 120, height: 90)
        let (rep, scale) = try render(view)
        let image = view.imageRect
        func alphaOutside(dx: CGFloat, dy: CGFloat) -> CGFloat {
            let p = CGPoint(x: image.maxX + dx, y: image.maxY + dy)
            guard let c = rep.colorAt(x: Int(p.x * scale), y: Int((view.bounds.height - p.y) * scale)) else { return -1 }
            return c.alphaComponent
        }
        let near = alphaOutside(dx: 1.5, dy: 0)
        let mid = alphaOutside(dx: 4, dy: 0)
        let far = alphaOutside(dx: MSPinGlow.pad - 1, dy: 0)
        #expect(near > 0.05, "紧贴外沿几乎没有东西（\(near)）⇒ 光晕没画出来")
        #expect(near > mid, "由内向外必须衰减：近=\(near) 中=\(mid)")
        #expect(mid > far, "外缘必须最淡：中=\(mid) 远=\(far)")
        #expect(far < near / 2, "近处与外缘差得太少（\(near) vs \(far)），看上去就是一条边框线")
    }

    @MainActor
    @Test("导出与剪贴板走的是渲染器，不经过视图：加光晕后内容像素一张不变")
    func exportIsUntouched() throws {
        let (_, view) = makePin(width: 60, height: 40)
        let baked = try #require(view.bakedImage(), "导出图渲染失败")
        #expect(baked.width == 120 && baked.height == 80, "导出尺寸应等于画布像素，got=\(baked.width)x\(baked.height)")
        var bytes = [UInt8](repeating: 0, count: baked.width * baked.height * 4)
        let ctx = CGContext(data: &bytes, width: baked.width, height: baked.height, bitsPerComponent: 8,
                            bytesPerRow: baked.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(baked, in: CGRect(x: 0, y: 0, width: baked.width, height: baked.height))
        #expect(bytes[0] == 30 && bytes[1] == 60 && bytes[2] == 90,
                "导出图第一个像素就不是源色（\(bytes[0]),\(bytes[1]),\(bytes[2])）⇒ chrome 混进了内容")
    }

    @MainActor
    @Test("几何只有一个来源：窗 = 图片 + 四周留白，图片原点在留白内侧")
    func geometryHasOneSource() throws {
        let (window, view) = makePin(width: 100, height: 60)
        let image = view.imageRect
        #expect(abs(image.minX - MSPinGlow.pad) < 0.001, "图片左边留白必须正好是 pad，got=\(image.minX)")
        #expect(abs(window.frame.width - (100 + MSPinGlow.pad * 2)) < 0.5, "窗宽 = 图片 + 左右留白")
        #expect(abs(window.frame.height - (60 + MSPinGlow.pad * 2)) < 0.5, "窗高 = 图片 + 上下留白")
        #expect(abs(image.width - 100) < 0.5 && abs(image.height - 60) < 0.5, "图片区域尺寸不许被留白吃掉")
        // 居中放置（⌘⇧V 那条）也要按窗尺寸算，否则画面会偏出 pad
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        #expect(abs(center.x - (200 + window.frame.width / 2)) < 0.5)
    }
}
