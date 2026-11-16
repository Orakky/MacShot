# 遮罩与选区（Overlay）

> 机制真源：遮罩窗的行为与渲染策略。视觉数值见 `docs/design/screens.md#UI-001`；状态迁移见 `docs/design/state-machines.md#ST-001`。

## 1. 窗型选择

| 项 | 取值 | 理由 |
|---|---|---|
| 类 | `NSWindow` borderless（非 `NSPanel`） | 遮罩需要成为会话期的事件焦点，但它**不夺系统前台**（见 §2） |
| level | `.statusBar`（=25）或 `.statusBar + 1`，**实测后定，记 ADR-019** | 必须盖住菜单栏（`.mainMenu`=24）与 Dock（`.dock`=20）。**原稿写"`.screenSaver` 之上"是错的**：`.screenSaver`=1000，远高于菜单栏，用它会让遮罩盖住屏幕保护/锁屏并可能与系统保护冲突；也不要用 `CGShieldingWindowLevel()`（那是锁屏层级）。正确的升序是 `.floating`(3) < `.modalPanel`(8) < `.dock`(20) < `.mainMenu`(24) < `.statusBar`(25) < `.popUpMenu`(101) |
| 覆盖范围 | **单个显示器的整屏**（Q-09 推荐 A） | 跨屏选区 P2；多屏时选光标所在屏 |
| 尺寸 | = 该显示器 `logicalFrame` | 位图 1:1 铺满，无缩放 |
| `ignoresMouseEvents` | false | 要接事件 |
| 是否激活 app | **不激活**：`NSApp.activate(ignoringOtherApps:)` 不调用；靠 `canBecomeKey` + 本地事件监视 | FR-SESS-003 要求提交后焦点回原 app |

风险：不激活的 borderless 窗能否稳定收到键盘事件，是 M-2 的头号实测项（`V-006`）。备选方案（按优先级）：`addLocalMonitorForEvents` → `NSResponder` 链 → 临时 `activate(ignoringOtherApps: false)`。这条未验证前，`screens.md` 的键盘-only 判据不能算通过。

## 2. 焦点与前台策略

- 会话开始：不改变 `NSWorkspace.frontmostApplication`（FR-SESS-003 判据）。
- 文字标注需要输入焦点时（`text` 工具），允许遮罩窗 `makeKey()`，但**不 activate app**；提交/取消后立刻 resign。
- 会话结束时把 key 状态交还：不调用任何"回到原 app"的 API（无法可靠做到），只保证 MacShot 自己没抢过前台。

## 3. 渲染策略

```
┌─────────────────────────────────────────┐
│ 整屏冻结帧位图（1:1 像素，无缩放）      │  ← 底：MSCaptureFrame.image
│   ┌───────遮罩(4 块矩形, α≈0.45)───────┐│
│   │  ┌─────────选区(清亮)─────────┐    ││  ← 洞：用 even-odd 填充或 4 块拼
│   │  │  选区内：位图 + 标注层      │    ││
│   │  └────────────────────────────┘    ││
│   └────────────────────────────────────┘│
│  读数标签 / 尺寸角标 / 工具条浮层        │  ← 只画脏区
└─────────────────────────────────────────┘
```

规则：
1. 选区内部显示**原尺寸位图 + 标注**，外部显示位图 + 遮罩，所以"遮罩下仍看得见内容"（Snipaste 行为）。
2. 遮罩用 4 块矩形（上/下/左/右）而不是 even-odd 大矩形：后者在选区拖动时整层重绘，前者只重绘变化的条带。
3. 拖动选区时**不重绘标注层**（内容不变，只换图层平移量）。
4. 位图绘制 `interpolationQuality = .none`：遮罩内 1:1，任何插值都是 bug。
5. 尺寸读数、角标、工具条是独立子层/子视图，避免每次动鼠标重画全屏位图。

## 4. 事件路由

```swift
struct OverlayPointerRouter {
    func pointerMoved(_ p: CGPoint)      // → 命中 MSSelectionGeometry.handle → 光标形状
    func pointerPressed(_ p: CGPoint)    // 决定 mode: .newSelection / .resize(handle) / .move / .draw(tool)
    func pointerDragged(_ p: CGPoint)    // mode 分发；选区变化走 delegate
    func pointerReleased(_ p: CGPoint)   // 收尾：normalize、最小尺寸、提交 Effect
}
```

模式判定（优先级从高到低）：
1. 当前有选中工具（`tool != .none`）且点在选区内 → 绘制标注，不动选区。
2. 点把手 → `resize`；点在选区内 → `move`；点在选区外 → `newSelection`（按下即清旧选区）。
3. `⇧` 按下时新建选区为"从中心展开"；`⌥` 为正方形约束；`⇧⌥` 组合留给 P1（对齐 Snipaste 的约束键需实测）。

几何一律委托 `MSSelectionGeometry`（`docs/architecture/modules.md#1`）。遮罩里出现任何手写坐标算术 = 评审必拦。

## 5. 键盘

| 键 | 行为 | 条目 |
|---|---|---|
| `Esc` | 取消会话（有文字编辑态时先退出编辑态，再一次 `Esc` 才取消会话，见 ST-003） | FR-SESS-002 |
| `Enter` / 双击选区 | 默认出口（Q-05 推荐档 A＝**贴出**并结束；设置可改复制） | FR-PIN-018 |
| `⌥Enter` | 复制并结束 | Q-05 |
| `⌘C` | 提交：复制 | FR-EXP-001 |
| `⌘P` / `⌘⇧P` | 提交：贴出 / 贴出并复制（Snipaste 里贴图的默认出口） | FR-PIN-001 |
| `⌘S` / `⌘⇧S` | 保存面板 / 免面板直存 | FR-EXP-003 |
| 方向键 | 移动选区 1px（P1，FR-CAP-013） | — |
| `Tab` | 窗口/元素检测模式切换（P1）；标注阶段切换形状变体（P1） | FR-CAP-011 |
| `R` | 重复上次区域（P1） | FR-CAP-012 |
| `⌘Z` / `⇧⌘Z` | 撤销/重做（标注阶段） | FR-ANN-005 |
| 数字 `1`–`5` | 笔宽档位（P1，档位属 Snipaste PRO） | FR-ANN-003 |

完整键位表只在 `docs/design/keymap.md`（真源），本表是引用。

## 6. 读数与提示元素

- 尺寸读数：`W×H` 设备像素（不是逻辑点），跟随选区右下角，边缘留 8pt；超出屏幕时翻到内侧。
- 位置读数：`X,Y`（全局逻辑）随读数一起显示（P1）。
- 缩放倍率提示：当显示器 scale ≠ 1 时显示 `@2x` 标记，避免用户困惑"为什么我拖了 100 得到 200"。
- 清空标注提示（Q-11）：选区变形且 `elements` 非空时出现，见 `docs/design/screens.md#UI-001`。

## 7. 放大镜（P1，先定契约不做实现）

- 出现条件：自动（拖拽时）或 `⌥` 强制（Snipaste 用 `Alt`，官方 S1）。
- 内容：以取样点为中心的近邻放大位图 + 像素网格线 + 中心高亮。
- 读数：`#RRGGBB` 默认，`⇧C` 切 RGB/HSL；`C` 复制到剪贴板。
- 采样：`MSImageSampler`（`MSCore`），对**冻结帧**采样，不对屏幕采样。
- 键位 `W/A/S/D` 逐像素：Snipaste 需要辅助功能权限（`docs/reference/snipaste-gap.md` §6），我们先记风险，开工前定 ADR。

## 8. 失败与边界

| 情况 | 行为 |
|---|---|
| 权限缺失（黑图） | 不进入 `frozen`，弹权限引导窗（FR-CAP-006） |
| 选区被拖成 0 面积 | `pointerReleased` 时小于 4px → 视为"点选"，走窗口/元素检测（P1）或取消（P0） |
| 会话中拔屏 | 用 `LayoutSnapshot`（FR-SESS-004） |
| 用户在遮罩期间切换 Space | 遮罩 `collectionBehavior` 含 `.canJoinAllSpaces`，跟着显示；快照内容不变（这是冻结语义，不是 bug） |
| 显示器 scale 变化（改了分辨率） | 同上，按快照 scale 出图；日志 `capture.display-snapshot-stale` |

## 9. 测试清单

1. `OverlayPointerRouter` 事件序列 → 选区结果（含把手/移动/新建三种 mode 的交错、`⇧`/`⌥` 约束）。
2. 渲染脏区断言：拖动选区时"标注层未被重绘"的计数（注入绘图计数器）。
3. 读数正确性：scale=2 下 100×100 逻辑 → 显示 `200×200`（与 `pixelRect` 一致）。
4. 键盘事件在"app 未激活"时可达性（实拍 `V-006`）。
5. 焦点归还：前台 app 前后不变（实拍）。
