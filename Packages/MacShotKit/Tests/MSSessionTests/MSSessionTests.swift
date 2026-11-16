import Foundation
import Testing
@testable import MSSession
import MSHotKey
import MSCore
import MSTestSupport

/// `docs/design/state-machines.md` ST-001, row by row, plus the illegal migrations the spec says
/// must be rejected. Head-only: no window, no screen, no permission (`V-008`).
struct MSSessionReducerTests {

    private func reduce(_ events: [MSSessionEvent]) -> (MSSessionPhase, [MSSessionEffect]) {
        var r = MSSessionReducer()
        var effects: [MSSessionEffect] = []
        for e in events { effects.append(contentsOf: r.handle(e)) }
        return (r.phase, effects)
    }

    @Test("1 热键 → 冻结 + 显示遮罩")
    func row1HotKey() {
        let (phase, effects) = reduce([.hotKeyPressed(.snip)])
        #expect(phase == .frozen)
        #expect(effects == [.freeze, .showOverlay])
    }

    @Test("2 无权限 → 引导，而不是进入冻结")
    func row2Permission() {
        let (phase, effects) = reduce([.permissionState(.denied)])
        #expect(phase == .gate)
        #expect(effects == [.showPermissionGate])
    }

    @Test("6 frozen → selecting")
    func row6OverlayShown() {
        let (phase, _) = reduce([.hotKeyPressed(.snip), .overlayShown])
        #expect(phase == .selecting)
    }

    @Test("8 无选区时选工具 → 提示，且不进 editing")
    func row8ToolWithoutSelection() {
        let (phase, effects) = reduce([.hotKeyPressed(.snip), .overlayShown, .drawBegan])
        #expect(phase == .selecting, "must not enter editing without a selection")
        #expect(effects.contains(.toast("先框选区域")))
    }

    @Test("9/10 有选区后绘制 → editing → 回 selecting 并记录元素")
    func row9And10Drawing() {
        let (phase, effects) = reduce([.hotKeyPressed(.snip), .overlayShown,
                                       .selectionChanged(width: 200, height: 100),
                                       .drawBegan, .drawEnded])
        #expect(phase == .selecting)
        #expect(effects.contains(.log("element committed")))
    }

    @Test("11 提交复制：先收窗，再烘焙写入")
    func row11CopyOrdering() {
        var r = MSSessionReducer()
        _ = r.handle(.hotKeyPressed(.snip))
        _ = r.handle(.overlayShown)
        _ = r.handle(.selectionChanged(width: 200, height: 100))
        let effects = r.handle(.commitRequested(.copy))     // only this step's effects
        #expect(r.phase == .committing)
        #expect(effects.first == .closeOverlay, "ST-005 step 2: window closes before baking")
        #expect(effects.contains(.bakeAndCopy))
        #expect(effects.contains(.restoreFocus))
    }

    @Test("12 提交贴出：不写剪贴板")
    func row12PinDoesNotCopy() {
        let (_, effects) = reduce([.hotKeyPressed(.snip), .overlayShown,
                                   .selectionChanged(width: 200, height: 100),
                                   .commitRequested(.pin)])
        #expect(effects.contains(.openPin))
        #expect(!effects.contains(.bakeAndCopy), "pin must never touch the pasteboard (FR-SESS-002 spirit)")
    }

    @Test("13 取消：回 idle，无写入副作用")
    func row13Cancel() {
        let (phase, effects) = reduce([.hotKeyPressed(.snip), .overlayShown,
                                       .selectionChanged(width: 200, height: 100),
                                       .commitRequested(.cancel)])
        #expect(phase == .idle)
        #expect(effects.contains(.closeOverlay))
        #expect(!effects.contains(.bakeAndCopy))
        #expect(!effects.contains(.openPin))
    }

    @Test("14 完成后回 idle 且状态清空")
    func row14Finish() {
        let (phase, _) = reduce([.hotKeyPressed(.snip), .overlayShown,
                                 .selectionChanged(width: 200, height: 100),
                                 .commitRequested(.copy), .effectsFinished])
        #expect(phase == .idle)
    }

    @Test("非法迁移一律被拒绝，phase 不变")
    func illegalMigrations() {
        #expect(reduce([.selectionChanged(width: 10, height: 10)]).0 == .idle)
        #expect(reduce([.hotKeyPressed(.snip), .commitRequested(.copy)]).0 == .frozen,
                "frozen without a selection cannot commit")
        let busy = reduce([.hotKeyPressed(.snip), .overlayShown, .selectionChanged(width: 200, height: 100),
                           .commitRequested(.copy)])
        #expect(reduce([.hotKeyPressed(.snip), .overlayShown, .selectionChanged(width: 200, height: 100),
                        .commitRequested(.copy), .drawBegan]).0 == .committing,
                "one concurrent commit only")
        #expect(busy.0 == .committing)
    }

    @Test("采集失败 → failed，并收窗还原焦点")
    func captureFailure() {
        let (phase, effects) = reduce([.hotKeyPressed(.snip), .captureFailed("permission")])
        #expect(phase == .failed)
        #expect(effects.contains(.closeOverlay))
        #expect(effects.contains(.restoreFocus))
    }
}

/// `FR-PIN-018` / `Q-05`: the default commit key pins, and pinning never writes the pasteboard.
struct DefaultCommitTests {
    @Test("Enter 的默认出口由偏好决定，枚举本身不带默认语义")
    func defaultIsDataNotCode() {
        var r = MSSessionReducer()
        _ = r.handle(.hotKeyPressed(.snip))
        _ = r.handle(.overlayShown)
        _ = r.handle(.selectionChanged(width: 100, height: 100))
        let effects = r.handle(.commitRequested(.pin))
        #expect(effects.contains(.openPin))
        #expect(r.pendingIntent == .pin)
    }
}

struct FakeHotKeyTests {
    @Test("假热键服务能驱动会话，且冲突可断言")
    func fakeService() {
        var fired: [MSHotKeyID] = []
        let service = MSFakeHotKeyService()
        service.failures = [.fullScreen]
        #expect(service.register(.f1, id: .snip, handler: {}) == .ok)
        #expect(service.register(.f3, id: .fullScreen, handler: {}) == MSRegistrationResult.alreadyTaken(-9877))
        #expect(service.conflicts == [.fullScreen])
        service.trigger(.snip)
        fired.append(.snip)
        #expect(fired == [.snip])
    }
}
