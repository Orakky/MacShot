import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSOverlay

/// `FR-CAP-016` / `UI-008` 放大镜。
///
/// 这里最要紧的一条不是"框画出来了"，而是**放大镜中心那一格的颜色必须等于取样色**：
/// 放大镜是取色的眼睛，它骗人比没有更糟。所以判据用像素量，不用状态变量（`V-044` 纪律）。
struct LoupeTests {
    /// 一张"可预测"的冻结帧：左上半红、右下蓝、中心 40×40 绿块，方便知道某个像素该是什么色。
    private static func makeFrame(width: Int = 800, height: Int = 500) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(200, 30, 40).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(MSColorRGBA.rgb(20, 60, 220).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        ctx.setFillColor(MSColorRGBA.rgb(30, 210, 90).cgColor)
        ctx.fill(CGRect(x: width / 2 - 20, y: height / 2 - 20, width: 40, height: 40))
        return ctx.makeImage()!
    }

    @MainActor
    private func makeView() -> MSOverlayView {
        let view = MSOverlayView(display: MSTestCard.display, frozenFrame: Self.makeFrame())
        view.frame = CGRect(origin: .zero, size: MSTestCard.display.logicalFrame.size)
        return view
    }

    @MainActor
    private func move(_ view: MSOverlayView, to p: CGPoint, option: Bool) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                         mouseCursorPosition: CGPoint(x: p.x, y: realHeight - p.y), mouseButton: .left)!
        cg.flags = option ? [.maskAlternate] : []
        view.mouseMoved(with: NSEvent(cgEvent: cg)!)
    }

    @MainActor
    @Test("⌥ 强制出现，松开就收回；放大镜必须画得出墨")
    func optionKeyShowsAndHidesTheLoupe() throws {
        let view = makeView()
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        move(view, to: center, option: false)
        #expect(!view.isLoupeVisible, "没拖拽也没按 ⌥ 不该出现")

        move(view, to: center, option: true)
        #expect(view.isLoupeVisible, "⌥ 必须强制呼出（规格：自动出现＝拖拽时、⌥ 强制）")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let box = MSLoupeModel.rect(anchor: center, bounds: view.bounds)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        // 视图 y 向上、位图行号向下：换算显式写（今天已经栽过四次，别再"顺手"）
        let rows = (Int((view.bounds.height - box.maxY) * scale))..<min(Int((view.bounds.height - box.minY) * scale), rep.pixelsHigh)
        let cols = Int(box.minX * scale)..<min(Int(box.maxX * scale), rep.pixelsWide)
        var ink = 0
        for y in rows where y >= 0 {
            for x in cols where x >= 0 { if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { ink += 1 } }
        }
        #expect(ink > 2000, "放大镜框内几乎没画东西（ink=\(ink)）")

        move(view, to: center, option: false)
        #expect(!view.isLoupeVisible, "⌥ 松开就该收回")
    }

    @MainActor
    @Test("数据层：近邻放大的中心像素必须**精确**等于取样色")
    func magnifiedCenterIsExactlyTheSampledPixel() throws {
        let view = makeView()
        let px = try #require(MSLoupeModel.pixel(view: CGPoint(x: 200, y: 125), viewHeight: 250,
                                                 imageSize: MSIntSize(width: 800, height: 500), scale: 2))
        let frame = Self.makeFrame()
        let sampled = try #require(MSImageSampler.sample(frame, pixelAt: px))
        let mag = try #require(MSImageSampler.magnified(frame, center: px, radius: MSLoupeModel.radius,
                                                        zoom: MSLoupeModel.zoom))
        let bmp = try #require(MSBitmap(image: mag))
        let center = MSIntPoint(x: mag.width / 2, y: mag.height / 2)
        let shown = try #require(bmp.sample(pixelAt: center))
        #expect(shown == sampled, "放大图中心=\(shown.hex()) 取样=\(sampled.hex()) ⇒ 17×17 的取窗错位了")
        #expect(mag.width == 170 && mag.height == 170, "17 像素 × 10 倍必须是 170，got=\(mag.width)x\(mag.height)")
    }

    @MainActor
    @Test("渲染层：放大镜中心格必须明显就是取样色（色差来自色彩管理，不许糊成隔壁）")
    func centerCellIsTheSampledColourNotAneighbour() throws {
        let view = makeView()
        let p = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        move(view, to: p, option: true)
        let sampled = try #require(view.loupeColor)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let cell = MSLoupeModel.centerCell(in: MSLoupeModel.rect(anchor: p, bounds: view.bounds)).insetBy(dx: 3, dy: 3)
        let col = Int(cell.midX * scale)
        let row = Int((view.bounds.height - cell.midY) * scale)
        let shown = try #require(rep.colorAt(x: col, y: row))
        func dist(_ r: Int, _ g: Int, _ b: Int) -> Int {
            let dr = abs(shown.redComponent * 255 - Double(r))
            let dg = abs(shown.greenComponent * 255 - Double(g))
            let db = abs(shown.blueComponent * 255 - Double(b))
            return Int((dr + dg + db).rounded())
        }
        // 夹具里三个候选色彼此差 300+：放大镜显示的不是取到的那个像素时，这里的 distance 会爆。
        let toSampled = dist(Int(sampled.red), Int(sampled.green), Int(sampled.blue))
        #expect(toSampled <= 60, "中心格与取样色差 \(toSampled)（色彩管理往返允许的小偏移）")
        #expect(dist(200, 30, 40) > 150 && dist(20, 60, 220) > 150,
                "中心格竟然更接近隔壁的红/蓝 ⇒ 取窗错位：toSampled=\(toSampled)")
    }

    @MainActor
    @Test("换算与 MSCore 那对函数同值：放大镜不许自带一套坐标系")
    func pixelMathUsesTheSameConversionAsEverythingElse() {
        let view = makeView()
        let sel = CGRect(x: 40, y: 60, width: 300, height: 200)
        let p = CGPoint(x: 210, y: 150)
        let viaCore = MSIntPoint.canvasPoint(of: p, in: view.bounds, scale: MSTestCard.display.scale)
        let viaLoupe = MSLoupeModel.pixel(view: p, viewHeight: view.bounds.height,
                                          imageSize: MSIntSize(width: 800, height: 500),
                                          scale: MSTestCard.display.scale)
        _ = sel
        #expect(viaCore == viaLoupe, "整屏选区下两条换算必须一致：core=\(viaCore) loupe=\(viaLoupe)")
    }

    @MainActor
    @Test("贴边镜像：四个角落的放大镜都必须留在屏内")
    func loupeStaysOnScreenAtEveryCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for (name, anchor) in [("左上", CGPoint(x: 8, y: bounds.maxY - 8)), ("右上", CGPoint(x: bounds.maxX - 8, y: bounds.maxY - 8)),
                               ("左下", CGPoint(x: 8, y: 8)), ("右下", CGPoint(x: bounds.maxX - 8, y: 8)),
                               ("正中", CGPoint(x: bounds.midX, y: bounds.midY))] {
            let box = MSLoupeModel.rect(anchor: anchor, bounds: bounds)
            #expect(bounds.contains(box), "\(name) 的放大镜出屏了：\(box) 不在 \(bounds)")
            let cell = MSLoupeModel.centerCell(in: box)
            #expect(box.contains(cell), "\(name) 的中心格跑到框外：\(cell)")
        }
    }

    @MainActor
    @Test("C 复制的串 == 读数条上的色值；⇧C 切格式")
    func copyStringTracksTheReadoutAndFormat() throws {
        let view = makeView()
        move(view, to: CGPoint(x: view.bounds.midX, y: view.bounds.midY), option: true)
        let hex = view.loupeCopyString()
        #expect(hex.hasPrefix("#") && hex.count == 7, "默认档必须是 #RRGGBB，got=\(hex)")
        #expect(MSLoupeModel.readout(color: view.loupeColor, pixel: view.loupePixel ?? .zero, format: .hex)
                .hasPrefix(hex), "读数条显示的串必须以复制内容开头，否则用户复制的不是他看到的")

        view.cycleLoupeFormat()
        let rgb = view.loupeCopyString()
        #expect(rgb.hasPrefix("rgb("), "⇧C 第二档应是 rgb(…)  got=\(rgb)")
        view.cycleLoupeFormat()
        #expect(view.loupeCopyString() == hex, "两档循环必须回到 hex（规格没有第三档）")
    }
}
