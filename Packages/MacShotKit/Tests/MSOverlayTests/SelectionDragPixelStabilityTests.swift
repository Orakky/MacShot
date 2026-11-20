import AppKit
import CoreGraphics
import MSCore
import MSAnnotate
import MSTestSupport
import Testing
@testable import MSOverlay

/// 用户 11-20 的两条描述合起来把问题钉死了：① 加一个箭头标注，按住拖动选区视窗，箭头有
/// "跟着移动"的闪烁感；② 我给出"位置 vs 边缘"二选一时，答的是**边缘在闪、位置不动**。
///
/// "位置不动、边缘闪"只有一种形状能同时成立：**同一帧里两份几何各算了一遍**——
/// 画布尺寸按 `round(宽 × scale)` 算，取样按"两条边各自 round 再相减"算。
/// 两者差 1 像素时，`render` 把 301px 的底图塞进 300px 的画布（再按选区放大画回屏幕），
/// 于是背景逐帧非整数重采样、标注却按整数画 ⇒ 框不动、里面的画面与箭头边缘在跳。
/// 小数原点每帧都在移动 ⇒ 差值在 0/1 之间反复 ⇒ 观感就是"抖"。
///
/// 所以这条判据**不留容差**，也不看耗时：
/// ① 取样尺寸 == 画布尺寸（逐帧，零容差）；
/// ② 箭头的设备行 `选区设备顶 + 画布 y` 逐帧完全相同（这是"屏幕位置不动"的定义本身）；
/// ③ 截图位图里箭头绿色包围盒逐帧完全相同（端到端，覆盖绘制段）。
struct SelectionDragPixelStabilityTests {
    private func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
        let src = CGEventSource(stateID: .combinedSessionState)
        let realHeight = NSScreen.screens.first?.frame.height ?? 1080
        let cg = CGEvent(mouseEventSource: src, mouseType: type,
                         mouseCursorPosition: CGPoint(x: p.x, y: realHeight - p.y), mouseButton: .left)!
        return NSEvent(cgEvent: cg)!
    }

    /// scale 1 —— 与用户实屏一致（KG251Q 1920×1080@x1.0）。夹具分辨率必须等于被测屏，
    /// 否则量级对不上（上一轮判据不敢开口的原因之一）。
    private static let oneX = MSDisplay(id: 1, logicalFrame: CGRect(x: 0, y: 0, width: 800, height: 500),
                                        visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 500),
                                        scale: 1, isMain: true, localizedName: "1x")

    /// 背景要是**有周期的条纹**：底图被非整数重采样时，条纹间距会变，像素级量得出来；
    /// 纯灰底（上一版夹具）对重采样完全不敏感，所以那条判据当时只能量到"位置"。
    @MainActor
    private func stripedFrame() -> CGImage {
        let ctx = CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<800 {
            let v: UInt8 = (x / 3) % 2 == 0 ? 90 : 191
            ctx.setFillColor(MSColorRGBA.rgb(v, v, v).cgColor)
            ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: 500))
        }
        return ctx.makeImage()!
    }

    /// 界面里不存在的纯绿，且必须与工具条/把手/高亮的蓝都不同色（撞色就会把 chrome 量进包围盒）。
    private func arrow() -> MSAnnotationElement {
        var style = MSAnnotationStyle.standard
        style.stroke = .rgba(0, 255, 0, 1)
        return MSAnnotationElement(kind: .arrow, points: [MSIntPoint(x: 40, y: 40), MSIntPoint(x: 150, y: 110)],
                                   style: style, z: 0)
    }

    @MainActor
    private func makeView(selection: CGRect) throws -> MSOverlayView {
        let view = MSOverlayView(display: Self.oneX, frozenFrame: stripedFrame())
        view.setSelection(selection)
        var doc = try #require(view.document, "setSelection 之后文档应已按真实像素建好")
        doc.elements.append(arrow())
        view.document = doc
        view.tool = .select
        return view
    }

    @MainActor
    private func snapshot(_ view: MSOverlayView) throws -> NSBitmapImageRep {
        view.needsDisplay = true
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 只扫**选区设备矩形内部**：上一版在整幅位图上找绿，结果第一帧把选区外的绿色 chrome
    /// 也量进包围盒（盒宽 380px、比箭头本身大得多）——量的就不是箭头了。
    private func greenBox(_ rep: NSBitmapImageRep, in scan: MSIntRect) -> (count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int) {
        var count = 0, minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
        for y in max(0, scan.minY)..<min(rep.pixelsHigh, scan.maxY) {
            for x in max(0, scan.minX)..<min(rep.pixelsWide, scan.maxX) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.greenComponent * 255 > 180 && c.redComponent * 255 < 110 && c.blueComponent * 255 < 110 {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return (count, minX, minY, maxX, maxY)
    }

    /// 一次纯平移拖动，逐帧记录三段真值并当场判定。
    /// 起点故意取**小数**（13.4 / 21.7 / 300.4 × 180.6）：整数起点会让"两条边分别取整"与
    /// "尺寸取整"永远相等，那条判据就变成空转（11-20 反证实测：整数起点的夹具跑不出红）。
    @MainActor
    private func runMove(steps: Int, dx: CGFloat, dy: CGFloat,
                         label: String) throws -> [(pair: Bool, devRow: Int, box: String, note: String)] {
        let start = CGRect(x: 13.4, y: 21.7, width: 300.4, height: 180.6)
        let view = try makeView(selection: start)
        let grab = CGPoint(x: start.maxX - 12, y: start.maxY - 12)   // 右下空白 ⇒ dragMode = .move
        view.mouseDown(with: mouse(.leftMouseDown, grab))
        #expect(view.dragModeForProbe == "move", "抓取点必须走「移动视窗」支路，实测 \(view.dragModeForProbe)")
        var rows: [(pair: Bool, devRow: Int, box: String, note: String)] = []
        for step in 0...steps {
            if step > 0 {
                view.mouseDragged(with: mouse(.leftMouseDragged,
                                              CGPoint(x: grab.x + CGFloat(step) * dx, y: grab.y + CGFloat(step) * dy)))
            }
            let sel = try #require(view.selection, "拖动过程中选区不该消失")
            let pixel = try #require(Self.oneX.pixelRect(forLogical: sel), "选区应落在屏内")
            let canvas = try #require(view.document?.canvasSize, "文档必须在")
            let elemY = view.document?.elements.first?.points.first?.y ?? -1
            let b = greenBox(try snapshot(view), in: pixel)
            // ① 取样与画布必须是同一个矩形；② 箭头的设备行 = 选区设备顶 + 画布 y
            rows.append((pixel.width == canvas.width && pixel.height == canvas.height,
                         pixel.minY + elemY,
                         b.count > 30 ? "\(b.minX),\(b.minY),\(b.maxX),\(b.maxY) c\(b.count)" : "丢失(\(b.count))",
                         "crop=\(pixel.width)x\(pixel.height) canvas=\(canvas.width)x\(canvas.height) elemY=\(elemY)"))
        }
        for (i, r) in rows.enumerated() { print("【\(label)】帧\(i) pair=\(r.pair) devRow=\(r.devRow) 盒=\(r.box) | \(r.note)") }
        return rows
    }

    @MainActor
    @Test("纯平移选区：取样矩形必须就是画布矩形，箭头的设备行与像素包围盒逐帧零变化")
    func pureMoveKeepsDeviceGeometryPaired() throws {
        // 每帧位移 0.37 / 0.23 pt —— 与真机日志同一量级（当时读到 maxY 每帧 +0.23）。
        let rows = try runMove(steps: 9, dx: 0.37, dy: 0.23, label: "平移")
        let broken = rows.filter { !$0.pair }.count
        #expect(broken == 0, "有 \(broken)/\(rows.count) 帧取样尺寸 ≠ 画布尺寸 ⇒ 底图被逐帧非整数重采样，这就是「框不动、边缘闪」")
        let devRows = Set(rows.map(\.devRow))
        #expect(devRows.count == 1, "箭头的设备行逐帧出现 \(devRows.count) 种 \(devRows.sorted()) ⇒ 相对屏幕在动，不是相对背景在动")
        let boxes = Set(rows.map(\.box))
        #expect(boxes.count == 1, "拖动视窗时箭头像素盒有 \(boxes.count) 种：\(boxes.sorted())")
    }
}
