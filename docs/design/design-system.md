# 设计系统（token 唯一真源）

> 真源：所有颜色、字号、间距、圆角、图标、动效数值**只在本文件定义**。`screens.md` 与代码只能引用 token 名。
> 状态：**待裁决**（数值是我的推荐，改一处即全局生效）。

## 1. 四条原则（评审时用来否决）

1. **内容优先**：UI 永远压在图片之上但不吃掉图片——工具条悬浮、可自动隐藏、绝不做模态遮罩。
2. **即时可逆**：任何动作 1 步内可撤销；破坏性动作（销毁贴图、清空标注）必须可见提示。
3. **系统一致优先于自定义**：能用系统控件（明暗、控件高度、SF 字体、SF Symbols）就不自绘；自绘只在画布/遮罩/贴图这三处。
4. **键盘是主路径**：四大件全链路可纯键盘完成（`keymap.md`），鼠标只是加速器。

## 2. 颜色

### 2.1 语义 token

| token | light | dark | 用途 |
|---|---|---|---|
| `overlay.scrim` | `#000000` @ 45% | `#000000` @ 55% | 遮罩暗化层 |
| `selection.stroke` | `#FFFFFF` @ 90% | `#FFFFFF` @ 90% | 选区描边（1pt） |
| `selection.stroke.inner` | `#000000` @ 55% | `#000000` @ 55% | 选区描边内侧 1pt（双线保证任何背景都看得见） |
| `selection.handle` | `#FFFFFF`，边 `#0A84FF` | `#D8D8D8`，边 `#0A84FF` | 8 个把手，直径 7pt |
| `float.surface` | `#F6F6F6` @ 96% | `#2A2A2C` @ 96% | 工具条/浮层底色 |
| `float.stroke` | `#000000` @ 12% | `#FFFFFF` @ 14% | 浮层描边 |
| `float.shadow` | `0 6 18 -4 #000000` @ 28% | 同 | 浮层投影 |
| `text.primary` | `#1D1D1F` | `#F2F2F7` | 读数、标签 |
| `text.secondary` | `#6E6E73` | `#A1A1A6` | 次要说明 |
| `text.onDark` | `#FFFFFF` | `#FFFFFF` | 遮罩上的读数（读数永远在暗背景上） |
| `accent` | `#0A84FF` | `#409CFF` | 焦点、当前工具、进度 |
| `danger` | `#FF3B30` | `#FF453A` | 销毁贴图、清空标注提示 |
| `warn` | `#FF9F0A` | `#FF9F0A` | 权限缺失、热键冲突 |
| `pin.badge.surface` | `#000000` @ 62% | `#000000` @ 62% | 贴图角标（未导出/倍率/透明度） |

### 2.2 标注默认色板（工具条上的 8 格，顺序固定）

| 位 | 十六进制 | 名称 | 默认用途 |
|---|---|---|---|
| 1 | `#E83347` | 红 | **默认描边色**（箭头/矩形） |
| 2 | `#FF9500` | 橙 | |
| 3 | `#FFCC00` | 黄 | 荧光笔默认 |
| 4 | `#34C759` | 绿 | |
| 5 | `#0A84FF` | 蓝 | |
| 6 | `#AF52DE` | 紫 | |
| 7 | `#000000` | 黑 | 文字默认 |
| 8 | `#FFFFFF` | 白 | |

规则：色板是**内容色**，不随明暗模式变化（截图标注要发给别人，颜色必须稳定）。第 9 格永远是"自定义/取色"入口。

## 3. 字体与排版

| token | 值 | 用途 |
|---|---|---|
| `font.ui` | 系统字体 13pt（`NSFont.systemFont`） | 常规控件 |
| `font.ui.small` | 系统 11pt | 角标、次要说明 |
| `font.readout` | 系统 12pt **等宽数字**（`monospacedDigit`） | `W×H`、坐标、倍率、透明度读数 |
| `font.float.title` | 系统中等 13pt | 浮层标题（P1） |
| 标注文字档 | 12 / 14 / 18 / 24 / 32 pt（存像素见 `annotate-model.md` §3） | 文字工具 |

- 中英混排：文案里不出现需要行高特调的字符；`W×H` 用 `×`（U+00D7）不用 `x`。
- 读数一律"数字+单位无空格"，如 `200×120 @2x`。
- 本地化：所有用户可见文案走 key（`ui.overlay.readout.size` 等），中英对照表真源在 `docs/protocol/coding-conventions.md` §9。

## 4. 间距、尺寸、圆角

| token | 值 | 用途 |
|---|---|---|
| `sp.1` | 4pt | 图标与文字之间 |
| `sp.2` | 8pt | 浮层内元素间距 |
| `sp.3` | 12pt | 浮层内边距 |
| `sp.4` | 16pt | 区块间距 |
| `sp.5` | 24pt | 设置窗分组间距 |
| `hit.min` | 24pt | 任何可点元素的最小命中边（可访问性硬线） |
| `ctrl.h` | 28pt | 工具条按钮高度 |
| `ctrl.h.small` | 22pt | 次级控件 |
| `bar.h` | 40pt | 标注工具条主体高度 |
| `radius.1` | 4pt | 小按钮/角标 |
| `radius.2` | 8pt | 浮层 |
| `radius.3` | 12pt | 设置窗卡片 |
| `sel.handle.size` | 7pt | 选区把手直径（视觉） |
| `sel.handle.hit` | 10pt | 选区把手命中半径（交互，≠ 视觉尺寸） |
| `stroke.thin` | 1pt | 选区、描边 |
| `shadow.float` | 见 `float.shadow` | 浮层 |

- 选区把手直径 7pt，但命中半径 10pt（`hit.min` 的一半），两者分离写在 `screens.md#UI-001`。
- 4pt 栅格：任何非 4 倍数的数值出现 = 需要说明理由（例如 22pt 的小控件高度来自系统控件自然高度）。

## 5. 图标

来源：**SF Symbols**（不引第三方图标库，ADR-015）。名称是候选，实现前必须在 Xcode 的 SF Symbols app 里核对可用性（**待核对**，`T-0xx`）。

| 工具/动作 | 候选 symbol | 备注 |
|---|---|---|
| 矩形 | `rectangle` | |
| 椭圆 | `oval` | |
| 箭头 | `arrow.up.right` | |
| 折线箭头 | `path.forward` / `curve` | 若无合适图形则自绘 12×12 |
| 画笔 | `pencil.line` | |
| 荧光笔 | `highlighter` | |
| 文字 | `character.cursor.ibeam` / `textformat` | |
| 序号徽章 | `number` | |
| 马赛克/模糊 | `mosaic` / `drop.fill` | 两种模糊用同一图标 + 样式条区分 |
| 橡皮擦 | `eraser.fill` | |
| 撤销 / 重做 | `arrow.uturn.backward` / `.forward` | |
| 复制 | `doc.on.doc` | |
| 保存 | `tray.and.arrow.down` | |
| 贴出 | `pin` | |
| 关闭 | `xmark` | |
| 透明度 | `circle.righthalf.filled` | |
| 取色 | `eyedropper` | |
| 设置 | `gearshape` | |
| 权限警告 | `exclamationmark.shield` | |

规则：图标只在工具条/菜单出现；正文按钮用文字，不用"图标+文字"混排（省宽度且避免中英长度差）。

## 6. 动效

| token | 值 | 用途 |
|---|---|---|
| `dur.instant` | 0（不闪） | 遮罩出现：**禁止淡入**（用户会以为卡了一下） |
| `dur.fast` | 100ms `easeOut` | 工具条出现/收起、按钮按下态 |
| `dur.normal` | 160ms `easeOut` | 贴图出现、样式条展开 |
| `dur.slow` | 220ms `easeInOut` | 设置窗动画、面板切换 |
| `dur.toast` | 180ms 出现 / 停留 1600ms / 120ms 消失 | 一次性提示 |

- 不做弹跳、不做缩放进入（贴图出现必须"立刻在"，因为它常被用来对照着看东西）。
- 尊重"减少动态效果"：`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 为真时全部动画降为 0（可访问性 NFR）。

## 7. 光标

| 场景 | 光标 |
|---|---|
| 遮罩内选区外 | 十字（`crosshair`） |
| 选区内移动 | 打开手（`openHand`） |
| 8 个把手 | 对应 8 向调整光标（系统提供，不自绘） |
| 绘制工具（箭头/画笔等） | 十字 + 工具角标（P1 自绘，P0 用十字） |
| 贴图 | 打开手（浏览态）/ 精确指针（编辑态） |
| 文字编辑 | I  beam |

## 8. 明暗与对比

- 全部 UI token 双色值（§2.1），跟随 `appearance` 设置（system/light/dark）。
- 标注色板不跟随（§2.2 规则）。
- 对比度门槛：`text.onDark` 对 `overlay.scrim` 之上的实际混合色 ≥ 4.5:1（WCAG 2.2 AA，NFR 可访问性类）；工具条文字对 `float.surface` 同样 ≥ 4.5:1。校验方法在 `docs/protocol/verification.md`。
- 读数永远画在半透明深色药丸底上，不裸放在截图内容之上（截图内容不可控，这是唯一可靠做法）。

## 9. 视觉反例（明确不要）

渐变背景、毛玻璃用在遮罩上（性能与语义都不对）、工具条加标题文字、给贴图加彩色边框当默认、图标加投影、任何"引导浮层/新功能气泡"（自用工具不需要）、启动欢迎窗、更新弹窗。
