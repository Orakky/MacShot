import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSPin

/// `B-028` 的最终形态：编辑态把贴图窗口在图片**下方**撑出一条工具带，
/// 图片区域（`imageRect`）与导出像素都不变。
///
/// 为什么不是折行：折行实测 `200×140` 要盖掉 75% 画面、`60×40` 要 985%（`E-060` 有算术表）。
/// 为什么不是子窗：多一个窗要管层级、跟随、销毁，收益一样但状态多一倍。
/// 极小贴图（预算 min(160pt, 图片高) 都不够）仍退回字母——那是诚实的边界，不是失败。
struct ToolbarFlowTests {
    @MainActor
    private func makePin(width: Int, height: Int) -> (MSPinWindow, MSPinView) {
        let ctx = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(MSColorRGBA.rgb(150, 150, 150).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width * 2, height: height * 2))
        let content = MSPinContent(document: MSAnnotationDocument(canvasSize: MSIntSize(width: width * 2, height: height * 2)),
                                   source: ctx.makeImage()!, scale: 2)
        let window = MSPinWindow(content: content, origin: NSPoint(x: 200, y: 200), menu: nil)
        return (window, window.pinView)
    }

    @MainActor
    @Test("200×140 的日常小贴图：撑高窗口后工具条可用，且画面一寸没被盖")
    func smallPinGetsToolbarWithoutCoveringImage() throws {
        let (window, view) = makePin(width: 200, height: 140)
        let frameBefore = window.frame
        #expect(view.stripHeight == 0, "非编辑态不该有工具带")

        view.isEditing = true
        #expect(view.stripHeight > 0, "撑高方案下 200×140 必须有工具带（折行方案在这里判为放不下）")
        #expect(abs(view.imageRect.height - 140) < 0.5, "图片区域必须还是 140pt，got=\(view.imageRect)")
        #expect(abs(window.frame.height - (140 + view.stripHeight)) < 0.5, "窗口只长高，图片不缩")
        #expect(abs(window.frame.maxY - frameBefore.maxY) < 0.5, "顶边不许跳：向下长")

        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        let layout = try #require(view.editToolbarLayout)
        #expect(layout.items.count == MSPinView.pinToolbarTools.count, "不许静默少画工具")
        #expect(layout.colors.count == MSAnnotationPalette.toolbar.count)
        for (_, box) in layout.items {
            #expect(box.maxY <= view.stripHeight + 0.5, "工具格必须待在工具带里，不许爬到画面上：\(box)")
            #expect(view.bounds.contains(box.insetBy(dx: -0.5, dy: -0.5)), "格子出界 \(box)")
        }
        for i in 0..<layout.items.count {
            for j in (i + 1)..<layout.items.count {
                #expect(layout.items[i].1.intersection(layout.items[j].1).isEmpty, "格子重叠＝命中会选错")
            }
        }

        view.isEditing = false
        #expect(view.stripHeight == 0, "退出编辑要把窗口缩回去")
        #expect(abs(window.frame.height - frameBefore.height) < 0.5, "窗口尺寸复原")
    }

    @MainActor
    @Test("导出像素里绝不能有工具带（`FR-EXP-002`：屏上有带、导出不该有）")
    func stripNeverEntersExport() throws {
        let (_, view) = makePin(width: 200, height: 140)
        let plain = view.bakedImage()
        view.isEditing = true
        let whileEditing = view.bakedImage()
        #expect(plain != nil && whileEditing != nil)
        #expect(whileEditing?.width == 400 && whileEditing?.height == 280,
                "导出尺寸恒等于画布像素，与工具带无关")
        guard let a = MSBitmap(image: plain!), let b = MSBitmap(image: whileEditing!) else {
            Issue.record("取不到位图"); return
        }
        #expect(a.bytes == b.bytes, "工具带渗进了导出像素")
    }

    @MainActor
    @Test("有工具带时，点在图片中心必须落在画布中心（`docPoint` 走 imageRect）")
    func docPointAccountsForTheStrip() throws {
        let (_, view) = makePin(width: 200, height: 140)
        view.isEditing = true
        #expect(view.imageRect.width == 200, "图片宽不变，got=\(view.imageRect)")
        let center = CGPoint(x: view.imageRect.midX, y: view.imageRect.midY)
        let canvasCenter = view.docPoint(center)
        // 画布是 width*2 × height*2 = 400×280（scale 2），中心即 (200,140)
        #expect(abs(canvasCenter.x - 200) <= 1 && abs(canvasCenter.y - 140) <= 1,
                "画布 400×280 的中心应落在 (200,140)，got=\(canvasCenter)")
        let bottomEdge = CGPoint(x: view.imageRect.minX, y: view.imageRect.minY)
        let atBottom = view.docPoint(bottomEdge)
        #expect(atBottom.x == 0 && abs(atBottom.y - 280) <= 1, "图片底边要落在画布底部（280），got=\(atBottom)")
    }

    @MainActor
    @Test("最后一行的格子点得到（绘制与命中同一份格子）")
    func lastRowIsClickable() throws {
        let (_, view) = makePin(width: 620, height: 400)
        view.isEditing = true
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        let layout = try #require(view.editToolbarLayout)
        let last = layout.items[layout.items.count - 1]
        let src = CGEventSource(stateID: .combinedSessionState)
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let point = CGPoint(x: last.1.midX, y: last.1.midY)
        let cg = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                         mouseCursorPosition: CGPoint(x: point.x, y: realHeight - point.y), mouseButton: .left)!
        view.mouseDown(with: NSEvent(cgEvent: cg)!)
        #expect(view.activeTool == last.0, "最后一行的 \(last.0) 点不到 ⇒ 画在那儿但点不着")
    }

    @MainActor
    @Test("工具带里的格子必须真画得出墨（V-044 纪律：不许只断言状态）")
    func stripActuallyPaints() throws {
        let (_, view) = makePin(width: 200, height: 140)
        view.isEditing = true
        let bigRect = view.bounds                       // 撑高后的矩形，两张渲染都用它
        guard let marked = view.bitmapImageRepForCachingDisplay(in: bigRect) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: bigRect, to: marked)
        let layout = try #require(view.editToolbarLayout)
        view.isEditing = false
        // 同一尺寸再渲染一次（此时没有工具带）：两把尺同高，差集才是"工具带画出来的东西"
        guard let plain = view.bitmapImageRepForCachingDisplay(in: bigRect) else { Issue.record("拿不到位图"); return }
        view.cacheDisplay(in: bigRect, to: plain)

        let scale = CGFloat(marked.pixelsWide) / bigRect.width
        var emptyCells = 0
        for (_, box) in layout.items {
            // 视图 y 向上、位图行号向下：换算必须显式，否则量到镜像位置（今天已经栽过三次）
            let r0 = Int((bigRect.height - box.maxY) * scale)
            let r1 = Int((bigRect.height - box.minY) * scale)
            var ink = 0
            for y in stride(from: r0, to: min(r1, marked.pixelsHigh), by: 2) {
                for x in stride(from: Int(box.minX * scale), to: Int(box.maxX * scale), by: 2) {
                    guard let a = plain.colorAt(x: x, y: y), let b = marked.colorAt(x: x, y: y) else { continue }
                    if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                        + abs(a.blueComponent - b.blueComponent) > 0.2 { ink += 1 }
                }
            }
            if ink == 0 { emptyCells += 1 }
        }
        #expect(emptyCells == 0, "\(emptyCells) 个格子算出了位置却什么都没画")
    }

    @MainActor
    @Test("编辑态里缩放：工具带跟着图片重算，绝不允许带比图片还高")
    func zoomRecomputesTheStrip() throws {
        let (window, view) = makePin(width: 200, height: 140)
        view.isEditing = true
        #expect(view.stripHeight > 0, "1× 时该有工具带")
        // 缩到 25%：图片只剩 35pt，预算 min(160, 35) 放不下两行 ⇒ 带必须缩掉，而不是压过画面
        view.zoom = 0.25
        #expect(view.stripHeight <= 35 + 0.5, "工具带不该比图片还高，got=\(view.stripHeight)")
        #expect(abs(window.frame.height - (35 + view.stripHeight)) < 0.5,
                "窗口高必须等于「缩放后的图片高 + 带」，got=\(window.frame.height)")
        view.zoom = 2
        #expect(view.stripHeight > 0, "放大回来工具带要在")
        #expect(abs(window.frame.height - (280 + view.stripHeight)) < 0.5, "2× 的账：280 + 带")
    }

    @MainActor
    @Test("60×40 的极小贴图：预算不够 ⇒ 不撑工具带，但字母仍可用")
    func tinyPinFallsBackHonestly() throws {
        let (window, view) = makePin(width: 60, height: 40)
        view.isEditing = true
        #expect(view.stripHeight == 0, "为 40pt 高的贴图撑一条 394pt 的工具带是荒谬的")
        #expect(abs(window.frame.height - 40) < 0.5, "窗口不该被撑大")
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        #expect(view.editToolbarLayout == nil)
        let src = CGEventSource(stateID: .combinedSessionState)
        let cg = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)!
        view.keyDown(with: NSEvent(cgEvent: cg)!)
        #expect(view.activeTool == .arrow, "工具带缺席时字母必须还能用")
    }
}
