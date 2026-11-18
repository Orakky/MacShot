import AppKit
import MSCapture
import MSCore
import MSOverlay
import MSSettings

/// `--dump-chrome <png>`：把遮罩 chrome（暗化层 + 选区 + 把手 + 读数 + 工具条）**离屏自绘**成 PNG。
///
/// 存在的理由：`E-015` 之后原生界面的几何一直只有数值断言、没有眼睛。这条路不需要采集，
/// 所以不碰 TCC、不弹权限、也不需要合成鼠标事件。
@MainActor
enum MSChromeDump {
    static func run(to path: String, loupe: Bool = false, draft: Bool = false) {
        guard let display = MSDisplayInventory.current().first else {
            print("FAIL 没有可用显示器"); exit(2)
        }
        let size = display.pixelSize
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("FAIL 建不成合成底图"); exit(3)
        }
        // 棋盘底：暗化层均不均匀、有没有盖住整屏，一眼看得出来
        let step = 64
        for y in stride(from: 0, to: size.height, by: step) {
            for x in stride(from: 0, to: size.width, by: step) {
                let light = ((x / step) + (y / step)) % 2 == 0
                ctx.setFillColor(NSColor(white: light ? 0.85 : 0.35, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: step, height: step))
            }
        }
        guard let frame = ctx.makeImage() else { print("FAIL 合成底图出图失败"); exit(3) }

        let window = MSOverlayWindow(display: display, frame: frame)
        let view = window.overlayView
        let logical = display.logicalFrame
        view.setSelection(CGRect(x: logical.midX - 210, y: logical.midY - 130, width: 420, height: 260))
        view.tool = .rect
        // draft 档：装**用户机器上真落盘的偏好**，再用不带 ⌥ 的真事件拖一个矩形。
        // 复现的是"截图标注拖到一半时屏幕上到底有什么"，不碰 TCC。
        var draftNote = ""
        if draft {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("MacShot", isDirectory: true)
            let prefs = MSSettingsStore(directory: dir).current
            view.autoLoupeWhileDragging = prefs.showMagnifierWhileDragging
            draftNote = "落盘 schema=\(prefs.schemaVersion) showMagnifierWhileDragging=\(prefs.showMagnifierWhileDragging)"
            let src = CGEventSource(stateID: .combinedSessionState)
            let realH = NSScreen.screens.first?.frame.height ?? 1080
            func mouse(_ type: CGEventType, _ p: CGPoint) -> NSEvent {
                let cg = CGEvent(mouseEventSource: src, mouseType: type,
                                 mouseCursorPosition: CGPoint(x: p.x, y: realH - p.y), mouseButton: .left)!
                return NSEvent(cgEvent: cg)!
            }
            let sel = view.selection!
            view.mouseMoved(with: mouse(.mouseMoved, CGPoint(x: sel.minX + 60, y: sel.maxY - 60)))
            view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: sel.minX + 60, y: sel.maxY - 60)))
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: sel.minX + 210, y: sel.maxY - 170)))
        }
        if loupe {
            // 放大镜只能由真事件驱动：合成一次带 ⌥ 的 mouseMoved，让它按生产路径出现。
            let src = CGEventSource(stateID: .combinedSessionState)
            let realH = NSScreen.screens.first?.frame.height ?? 1080
            let anchor = CGPoint(x: logical.midX + 60, y: logical.midY - 20)
            let cg = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                             mouseCursorPosition: CGPoint(x: anchor.x, y: realH - anchor.y), mouseButton: .left)!
            cg.flags = CGEventFlags.maskAlternate
            view.mouseMoved(with: NSEvent(cgEvent: cg)!)
        }
        print("   loupe visible=\(view.isLoupeVisible) autoWhileDragging=\(view.autoLoupeWhileDragging) \(draftNote)")
        if draft { print("   拖拽中 draft=\(String(describing: view.draftKindForProbe)) 已提交元素=\(view.committedElementCount)") }
        view.needsDisplay = true
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("FAIL 离屏渲染拿不到位图"); exit(4)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("FAIL PNG 编码失败"); exit(5)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("FAIL 写文件失败：\(path) — \(error.localizedDescription)"); exit(6)
        }
        print("→ \(path) \(size.width)x\(size.height) selection=420x260 tool=rect")
        exit(0)
    }
}
