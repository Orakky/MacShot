import Foundation
import Testing
@testable import MSCore

/// The measured rounding cases from `docs/adr/ADR-013`: both edges round independently, so the
/// crop never exceeds the requested span. These numbers are arithmetic, not opinions.
struct MSIntGeometryTests {

    @Test("两条边分别取整 vs naive（1.799x 与 1x 半点坐标）")
    func roundingContract() {
        #expect(MSIntRect(flippedLogical: CGRect(x: 100.5, y: 0, width: 200.5, height: 10), scale: 1.799).width == 360)
        #expect(MSIntRect(flippedLogical: CGRect(x: 100.5, y: 0, width: 200.5, height: 10), scale: 1.0).width == 200)
        #expect(MSIntRect(flippedLogical: CGRect(x: 0.5, y: 0, width: 100.5, height: 10), scale: 1.0).width == 100)
        #expect(MSIntRect(flippedLogical: CGRect(x: 64.5, y: 0, width: 37.5, height: 10), scale: 1.0).width == 37)
        // 2x: contract and naive agree — the earlier claim that this rule targets Retina was wrong.
        #expect(MSIntRect(flippedLogical: CGRect(x: 100.5, y: 0, width: 200.5, height: 10), scale: 2.0).width == 401)
    }

    @Test("像素尺寸永不超过请求范围")
    func neverExceedsRequestedSpan() {
        for scale in [1.0, 1.5, 1.6, 1.799, 2.0, 3.0] {
            for x in stride(from: 0.0, through: 300.0, by: 0.25) {
                for w in stride(from: 4.0, through: 120.0, by: 1.75) {
                    let r = MSIntRect(flippedLogical: CGRect(x: x, y: 0, width: w, height: 8), scale: scale)
                    #expect(CGFloat(r.minX) <= x * scale + 0.5)
                    #expect(CGFloat(r.maxX) >= x * scale + w * scale - 0.5)
                    #expect(CGFloat(r.maxX) <= (x + w) * scale + 1.0)
                }
            }
        }
    }

    @Test("交集 / 并集 / 包含")
    func setOperations() {
        let a = MSIntRect(x: 0, y: 0, width: 10, height: 10)
        let b = MSIntRect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.intersection(b) == MSIntRect(x: 5, y: 5, width: 5, height: 5))
        #expect(a.union(b) == MSIntRect(x: 0, y: 0, width: 15, height: 15))
        #expect(a.intersection(MSIntRect(x: 20, y: 20, width: 5, height: 5)) == nil)
        #expect(a.contains(MSIntPoint(x: 9, y: 9)))
        #expect(!a.contains(MSIntPoint(x: 10, y: 10)), "max edge is exclusive")
    }
}

struct MSDisplaysTests {
    private func display(_ frame: CGRect, scale: CGFloat) -> MSDisplay {
        MSDisplay(id: 7, logicalFrame: frame, visibleFrame: frame, scale: scale, isMain: true, localizedName: "T")
    }

    @Test("选区裁剪到显示器本地像素，含 y 翻转")
    func localPixelRect() {
        // Display 1512x982 @2x at origin (0,0): AppKit y-up means the top of the screen is maxY.
        let d = display(CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
        let top = d.pixelRect(forLogical: CGRect(x: 0, y: 982 - 100, width: 200, height: 100))
        #expect(top?.minY == 0, "a band touching the top of the screen starts at pixel row 0")
        #expect(top?.width == 400)
        #expect(top?.height == 200)
    }

    @Test("副屏负坐标也能换算")
    func secondaryDisplayNegativeOrigin() {
        let d = display(CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
        let r = d.pixelRect(forLogical: CGRect(x: -1920, y: 1070, width: 10, height: 10))
        #expect(r == MSIntRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("越界选区被钳制而不是崩溃")
    func clampsOutOfDisplaySelection() {
        let d = display(CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        #expect(d.pixelRect(forLogical: CGRect(x: 90, y: 90, width: 50, height: 50))?.width == 20)
        #expect(d.pixelRect(forLogical: CGRect(x: 200, y: 200, width: 10, height: 10)) == nil)
    }
}

struct MSSelectionGeometryTests {
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 120)

    /// Handle names follow screen direction in AppKit space (y grows up), so `.top` == maxY.
    /// Getting this backwards flips every resize gesture, hence the explicit four-corner case.
    @Test("角、边、体内、体外")
    func handleHitTesting() {
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 100, y: 220), of: rect) == .topLeft,  "minX/maxY = 左上")
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 300, y: 100), of: rect) == .bottomRight, "maxX/minY = 右下")
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 200, y: 100), of: rect) == .bottom, "minY = 下边")
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 200, y: 220), of: rect) == .top,    "maxY = 上边")
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 180, y: 160), of: rect) == .body)
        #expect(MSSelectionGeometry.handle(at: CGPoint(x: 400, y: 400), of: rect) == .none)
    }

    @Test("拖过对面角会翻转而不是产生负尺寸")
    func flippingDragNormalizes() {
        let out = MSSelectionGeometry.resized(by: CGSize(width: -400, height: -300), handle: .bottomRight, from: rect)
        #expect(out.width >= MSSelectionGeometry.minimumSize)
        #expect(out.height >= MSSelectionGeometry.minimumSize)
        #expect(out.minX <= rect.maxX - 400 + 1)
    }

    @Test("移动不会离开边界")
    func moveClampsToDesktop() {
        let out = MSSelectionGeometry.moved(by: CGSize(width: 5000, height: 5000), rect: rect,
                                           clampTo: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(out.maxX == 1000)
        #expect(out.maxY == 800)
    }

    @Test("吸附命中与未命中")
    func snapping() {
        #expect(MSSelectionGeometry.snapped(100.4, to: [0, 100, 200], tolerance: 1) == 100)
        #expect(MSSelectionGeometry.snapped(103, to: [0, 100, 200], tolerance: 1) == nil)
    }
}

/// 热键改绑的接受/拒绝规则（FR-HOT-002）。这条判错的结果是"用户改了键，app 从此吃字"，
/// 所以规则必须是纯函数 + 有表，不能留在 UI 回调里。
struct MSKeyBindabilityTests {
    private func rule(_ code: UInt16, command: Bool = false, option: Bool = false,
                      control: Bool = false, shift: Bool = false) -> MSKeyCombo.Bindability {
        MSKeyCombo.bindability(keyCode: code, command: command, option: option, control: control, shift: shift)
    }

    @Test("纯功能键可绑定，但要提示 fn")
    func plainFunctionKeys() {
        #expect(rule(122) == .functionKeyNeedsHint)                    // F1
        #expect(rule(99, command: true) == .ok)                        // ⌘F3
    }

    @Test("普通字符键必须有修饰键，否则拒绝")
    func ordinaryKeysNeedModifier() {
        #expect(rule(0) == .needsModifier)                             // A
        #expect(rule(0, command: true) == .ok)                         // ⌘A
        #expect(rule(0, option: true) == .ok)                          // ⌥A
        #expect(rule(0, shift: true) == .needsModifier, "只有 ⇧ 不算修饰键")
    }

    @Test("Esc / Space / Return 被拒（会被系统或输入法吃掉）")
    func reservedKeys() {
        #expect(rule(53, command: true) == .reserved)
        #expect(rule(49, command: true, option: true) == .reserved)
    }

    @Test("默认值本身必须通过自己的规则（否则首启就是坏体验）")
    func defaultsAreLegal() {
        for combo in [MSKeyCombo.f1, MSKeyCombo.f3, MSKeyCombo(keyCode: 0, command: true)] {
            #expect(MSKeyCombo.bindability(keyCode: combo.keyCode, command: combo.command,
                                           option: combo.option, control: combo.control, shift: combo.shift).isBindable,
                    "\(combo.display) 应可绑定")
        }
    }

    @Test("显示名与 keyCode 一一对应，不再出现 F1 显示成 A 的那类错位")
    func displayMatchesCode() {
        #expect(MSKeyCombo.f1.display == "F1")
        #expect(MSKeyCombo.f3.display == "F3")
        #expect(MSKeyCombo(keyCode: 0, command: true).display == "⌘A")
        // Apple 的修饰键次序是 ⌃⌥⇧⌘，所以 ⌥ 在 ⌘ 之前才是规范写法。
        #expect(MSKeyCombo(keyCode: 1, command: true, option: true).display == "⌥⌘S")
        #expect(MSKeyCombo(keyCode: 0, command: true).display == "⌘A", "keyCode 0 必须是 A，不能被当成未知键")
        // 查表落空时绝不允许静默变成 0 号键（A）——这正是 11-16 那个 bug 的形状
        #expect(MSKeyCombo(keyCode: 122).display != "A")
    }
}
