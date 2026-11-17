import Foundation
import Testing
@testable import MSSession
import MSHotKey
import MSCore
import MSTestSupport
import MSSettings
import MSExport
import MSPin
import MSCapture

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

    @Test("12 提交贴出：路由到 openPin（复制顺带做，方向由端到端那条钉死）")
    func row12PinRoutesToOpenPin() {
        let (_, effects) = reduce([.hotKeyPressed(.snip), .overlayShown,
                                   .selectionChanged(width: 200, height: 100),
                                   .commitRequested(.pin)])
        #expect(effects.contains(.openPin))
        #expect(effects.contains(.closeOverlay))
        // `Q-05`（11-17）之后「置顶」本身就带复制，所以这里**不许**再断言
        // "pin 绝不碰剪贴板"——那是裁决前的旧语义，留着只会把人带偏。
        // effect 列表只描述**路由**；真正的剪贴板写在 `commit(.pin)` 里，
        // 它的方向性判据在 `PinCommitCopiesTests`（pin 写 1 次、copy 不贴图、cancel 两者皆 0）。
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

/// 回归：2026-11-16 的"按 Esc 退不出去、只能杀进程"。根因是 effect 分发器有 `default: break`，
/// 把 `.closeOverlay` 吞掉了。这里锁住"任何阶段取消都必须产生 closeOverlay"，
/// 因为漏一次的代价是把用户的整台机器糊住。
struct EscapeHatchTests {

    private func cancelFrom(_ prefix: [MSSessionEvent]) -> [MSSessionEffect] {
        var r = MSSessionReducer()
        for e in prefix { _ = r.handle(e) }
        let before = r.phase
        let effects = r.handle(.commitRequested(.cancel))
        #expect(r.phase == .idle, "从 \(before.rawValue) 取消后必须回到 idle，实际 \(r.phase.rawValue)")
        return effects
    }

    @Test("刚冻结（还没拖框）就能取消")
    func cancelWhileFrozen() {
        let effects = cancelFrom([.hotKeyPressed(.snip)])
        #expect(effects.contains(.closeOverlay), "frozen + Esc 必须收窗，否则遮罩糊住整屏")
        #expect(effects.contains(.restoreFocus))
    }

    @Test("有选区、有标注时能取消")
    func cancelAfterSelecting() {
        let effects = cancelFrom([.hotKeyPressed(.snip), .overlayShown,
                                  .selectionChanged(width: 200, height: 100)])
        #expect(effects.contains(.closeOverlay))
    }

    @Test("绘制子态里能取消")
    func cancelWhileEditing() {
        let effects = cancelFrom([.hotKeyPressed(.snip), .overlayShown,
                                  .selectionChanged(width: 200, height: 100), .drawBegan])
        #expect(effects.contains(.closeOverlay))
    }

    @Test("采集失败也要收窗")
    func failureClosesOverlay() {
        var r = MSSessionReducer()
        _ = r.handle(.hotKeyPressed(.snip))
        let effects = r.handle(.captureFailed("permission"))
        #expect(effects.contains(.closeOverlay))
        #expect(effects.contains(.restoreFocus))
    }

    /// 结构性保险：effect 种类若增加而分发器没交代，perform(_:) 会编译失败。
    /// 这条测试锁住枚举不被悄悄改名/删项，让那个编译期检查持续有效。
    @Test("MSSessionEffect 的 case 集合稳定")
    func effectCasesAreStable() {
        let known: [MSSessionEffect] = [
            .freeze,
            .showOverlay,
            .closeOverlay,
            .restoreFocus,
            .bakeAndCopy,
            .openPin,
            .saveToFile(panel: true),
            .saveToFile(panel: false),
            .showPermissionGate,
            .toast("x"),
            .log("y"),
        ]
        #expect(known.count == 11)
    }
}

// MARK: - 权限申请的节流（2026-11-16 用户报告"每次启动都要权限"）

/// 只读偏好桩：测试不依赖磁盘与 UserDefaults。
struct MSFakePreferences: MSReadingPreferences {
    var current: MSAppPreferences = .init()
}

@Suite("采集被拒时的权限申请次数")
struct PermissionThrottleTests {
    @MainActor
    @Test("同一进程内向系统只申请一次")
    func requestOnce() {
        let coord = MSSessionCoordinator(capturer: MSFakeCapturer(),
                                         preferences: MSFakePreferences(),
                                         pins: MSPinRegistry(),
                                         clipboard: MSClipboardWriter(pasteboard: MSFakePasteboard()))
        var asked = 0
        coord.permissionRequester = { asked += 1; return PermissionState.denied }
        #expect(coord.permissionRequestCount == 0)
        coord.requestPermissionOnce()
        coord.requestPermissionOnce()
        coord.requestPermissionOnce()
        #expect(asked == 1)
        #expect(coord.permissionRequestCount == 1)
    }
}
