import CoreGraphics
import Testing
@testable import MSOverlay

/// 遮罩是全屏模态：取消入口必须"看得见、点得到、位置可预期"。
/// 11-16 的事故是取消只有键盘一条路，而键又没送到视图（B-022）。
struct OverlayChromeTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("取消按钮的命中区不小于 44pt（可访问性硬线）")
    func hitTargetIsLargeEnough() {
        let hit = OverlayChrome.cancelHitRect(in: screen)
        #expect(hit.width >= 44 && hit.height >= 44)
        #expect(OverlayChrome.cancelVisual < OverlayChrome.cancelHit)
    }

    @Test("命中区包含视觉区，且四角都在屏幕内")
    func hitContainsVisualAndStaysOnScreen() {
        let hit = OverlayChrome.cancelHitRect(in: screen)
        let visual = OverlayChrome.cancelVisualRect(in: screen)
        #expect(hit.contains(CGPoint(x: visual.midX, y: visual.midY)), "视觉中心必须落在命中区内")
        #expect(hit.minX >= screen.minX && hit.maxX <= screen.maxX)
        #expect(hit.maxY <= screen.maxY, "y 向上：靠 maxY 一侧才是屏幕上方")
    }

    @Test("位置固定在左上角，不随选区变化")
    func positionIsStable() {
        let a = OverlayChrome.cancelHitRect(in: screen)
        let b = OverlayChrome.cancelHitRect(in: CGRect(x: 0, y: 0, width: 1280, height: 800))
        #expect(a.minX == b.minX, "左边距固定，用户闭着眼也能点")
        #expect(a.maxX < screen.midX, "不在右侧，避免与菜单栏控制中心混淆")
    }

    @Test("极小屏幕也不会把按钮挤出可视区")
    func tinyDisplayStillHasVisibleCancel() {
        let small = CGRect(x: 0, y: 0, width: 320, height: 200)
        let hit = OverlayChrome.cancelHitRect(in: small)
        #expect(small.contains(hit.insetBy(dx: -0.5, dy: -0.5)))
    }
}
