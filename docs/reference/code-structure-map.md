# MacShot 代码结构图谱（模块关系 · 函数职责 · 调用链）

> 本文**只是引用，不是真源**：范围与命名服从 `docs/charter.md`，决策正文服从 `docs/adr/`，需求与判据服从 `docs/requirements/` 与 `docs/protocol/verification.md`。
> 本文回答的是一件事：**代码块之间怎么连、每个函数负责哪一段**。凡与上述真源不一致，以真源为准，并把冲突登记进 `docs/tasks/blocked.md`。

## 0. 怎么读这份文档

| 约定 | 说明 |
|---|---|
| 定位方式 | `路径:行号`，行号取自已发布这轮的提交（`8e9d0eb`，0.1.2）。**行号会漂，符号名不会**：找不到就用符号名反查（`grep -rn "func canvasSize" Packages App`）。 |
| 路径基准 | 仓库根。包内文件一律写成 `Packages/MacShotKit/Sources/<模块>/<文件>.swift`，正文里简写成 `MSOverlay/MSOverlayView.swift:316`。 |
| 表头 | `作用` = 这个函数在结构上承担的那一段；`调用者` = 实际存在的入口（含测试）；`—` = 当前无调用者（这类条目集中登记在 §12）。 |
| ID | 行文中出现的 `V-`/`E-`/`FR-`/`ADR-`/`B-`/`T-` 是台账编号，正文不复制它们的结论，只说明"这段代码为什么长成这样"。 |

三条读码路线，按你想解决的问题选：

1. **想懂"一张图怎么从屏幕走到剪贴板"** → §2 数据流 → §5.2/5.7 调用链 → §4.3/§4.5/§4.8 三个模块。
2. **想改交互（选区、标注、放大镜）** → §3 坐标契约 → §7 绘制顺序 → §8 事件路由 → `MSOverlay/MSOverlayView.swift`。
3. **想知道"加一个功能要碰哪几个文件"** → §13.2 的练习清单，每条都写明了必须同批改的家。

## 1. 物理结构

### 1.1 目录 → 产物

| 目录 | 是什么 | 进不进产物 |
|---|---|---|
| `App/` | 组合根：7 个文件，负责装配、状态栏、设置窗、权限窗、更新器、toast、一堆 CLI 探针 | 是 |
| `Packages/MacShotKit/Sources/` | 9 个能力/编排模块 + 1 个测试替身模块，**全部逻辑代码在这里** | 是（静态链进 .app） |
| `Packages/MacShotKit/Tests/` | 7 个测试 target，swift-testing | 否 |
| `Config/Info.plist` | 版本号、`LSUIElement`、bundle 标识 | 是 |
| `assets/branding/` | 品牌 SVG（应用图标 + 菜单栏模板图） | 是（经 `make icon`/`inject-brand`） |
| `scripts/` | 4 个门禁脚本 + 构建/发布/探针辅助脚本 | 否 |
| `docs/` | 规格与台账（真源） | 否 |
| `prototypes/index.html` | 可操作原型，用来校对手感与几何 | 否 |
| `build/`、`Derived/`、`.idea/` | 产物与 IDE 状态 | 不入库 |

### 1.2 模块清单与规模

源码 9 个交付模块共 5,388 行，另有测试替身 `MSTestSupport` 146 行；`App/` 2,086 行；单测 4,238 行（32 个文件、184 个 `@Test` 声明）。

| 模块 | 文件数 | 行数 | 一句话职责 | 允许 import 的兄弟模块 |
|---|---:|---:|---|---|
| `MSCore` | 10 | 833 | 坐标/几何/图像取样/值类型/日志/更新纯逻辑，**无 AppKit** | — |
| `MSSettings` | 1 | 204 | 偏好结构体 + 版本迁移 + 读写盘 | `MSCore` |
| `MSHotKey` | 1 | 170 | Carbon 全局热键注册与回调分发 | `MSCore` |
| `MSCapture` | 2 | 192 | 冻结帧采集、显示器清单、权限探测 | `MSCore` `MSSettings` |
| `MSAnnotate` | 8 | 896 | 标注文档模型、渲染器、命中几何、撤销、工具条度量，**无 AppKit** | `MSCore` |
| `MSOverlay` | 5 | 1542 | 遮罩窗/视图：选区、绘制、放大镜、chrome | `MSCore` `MSCapture` `MSAnnotate` `MSSettings` |
| `MSPin` | 2 | 678 | 贴图窗/视图/注册表 | `MSCore` `MSSettings` `MSAnnotate` |
| `MSExport` | 1 | 212 | 烘焙、编码（DPI）、剪贴板写入、文件导出、命名模板 | `MSCore` `MSAnnotate` |
| `MSSession` | 1 | 661 | 状态机 + 副作用编排，**唯一持有活 UI 对象的包内位置** | 其余 8 个全部 |
| `MSTestSupport` | 1 | 146 | 测试卡、假采集器、假剪贴板、假热键、假文件 | `MSCore` `MSCapture` `MSAnnotate` `MSSession` |

依赖方向由 `Packages/MacShotKit/Package.swift:5-8`（模块顺序）与 `:18-44`（每个 target 的 dependencies）声明，并由 `scripts/check-deps.sh:7-21` 里**另一份**允许表机检。两处必须同批改——这是本项目最常见的"一个事实两个家"的例外，改一边另一边就红。

### 1.3 分层

```
装配层   App/main.swift（CLI 分发）· App/MSAppDelegate.swift（唯一装配点）
           │ 注入：capturer / preferences / pins / clipboard / hotKeys
编排层   MSSession.MSSessionReducer（纯）· MSSessionCoordinator（副作用）
           │ 只通过 delegate 与 effect 与表面说话
表面层   MSOverlay（遮罩）· MSPin（贴图）        ← 只有这两个 import AppKit 的绘制代码
           │ 共用
能力层   MSCapture · MSAnnotate · MSExport · MSHotKey · MSSettings
           │ 全部下沉到
值层     MSCore（几何 / 颜色 / 帧 / 意图 / 日志 / 接缝协议）
```

结构上最该记住的三条边：

1. **`MSOverlay` 与 `MSPin` 互不认识**（都不在对方的允许表里）。它们要共用的一切——工具表、色板、工具条度量、图标事实表、撤销栈——**必须下沉到 `MSAnnotate`**。`MSAnnotate/MSTool.swift:4-5` 和 `MSAnnotate/MSAnnotationToolbar.swift:6-8` 两段注释就是这两次下沉的记录。
2. **`MSSession` 不认识 `App/`**。它把"要做什么"以 `MSSessionEffect` 枚举交出去（`MSSession/MSSessionCoordinator.swift:33-49`），实际动手的人就在同文件的 `perform(_:)`（`:617-635`）；真正的系统能力（剪贴板、TCC、网络、登录项）由 `App/` 注入。
3. **能力模块不许摸 `NSPasteboard` / 文件系统 / 时钟**。三条薄接缝协议在 `MSCore/MSExternalSeams.swift`，生产实现在 `App/`，假实现在 `MSTestSupport`（见 §9）。

## 2. 数据流：一条像素的接力

### 2.1 主链

| 阶段 | 类型 | 谁产生 | 谁消费 |
|---|---|---|---|
| ① 环境快照 | `MSDisplay`（`MSCore/MSDisplay.swift:7`） | `MSDisplayInventory.current()`（`MSCapture/MSDisplayInventory.swift:9`） | 采集器、遮罩窗、裁剪器 |
| ② 整屏冻结帧 | `MSCaptureFrame`（`MSCore/MSCaptureFrame.swift:6`，含 `image`+`scale`+`sourcePixelRect`） | `ScreenCaptureKitCapturer.freeze(display:)`（`MSCapture/ScreenCapture.swift:39`） | 遮罩当背景；提交时当裁剪源 |
| ③ 选区（视图） | `CGRect`，AppKit 逻辑点 y-up | 用户拖拽 → `MSOverlayView.selection`（`MSOverlay/MSOverlayView.swift:167`） | 绘制、命中、工具条摆放 |
| ④ 选区（设备） | `MSIntRect`，像素 y-down | `MSDisplay.pixelRect(forLogical:)`（`MSCore/MSDisplay.swift:35`） | 取样、读数药丸、裁剪 |
| ⑤ 画布文档 | `MSAnnotationDocument`（`MSAnnotate/MSAnnotationDocument.swift:97`） | `MSOverlayView.ensureDocument(for:)`（`:308-312`）/ `MSPinContent` | 渲染器、撤销栈 |
| ⑥ 元素 | `MSAnnotationElement`（`…:55`），`points` 是**画布像素 y-down** | 拖拽草稿 `draft` 落定（`MSOverlay/MSOverlayView.swift:951-981`） | 渲染器逐类绘制、命中测试 |
| ⑦ 烘焙 | `CGImage`（尺寸恒等于 `canvasSize`） | `MSAnnotationRenderer.render(_:source:intent:)`（`MSAnnotate/MSAnnotationRenderer.swift:22`） | 剪贴板、保存、贴图显示 |
| ⑧ 编码 | `Data`（PNG/JPEG，DPI=72×scale） | `MSImageEncoder`（`MSExport/MSExport.swift:56-83`） | `NSPasteboard` / 磁盘 |

关键结构性事实：**②只发生一次**。会话期内所有裁剪都从这张位图里走（`MSOverlay/MSOverlayView.swift:495-499`、`MSSession/MSSessionCoordinator.swift:381`），绝不再次回源屏幕。这就是"遮罩画面是冻住的"与"选区怎么改都不重新截图"的同一个实现。

### 2.2 出口分叉

```
CGImage（⑦）
 ├─ .copy      → MSImageEncoder.png → MSClipboardWriter.write → MSSystemPasteboard（一次 clearContents + 一次 writeObjects）
 ├─ .pin       → MSPinContent(document, source, scale) → MSPinRegistry.open → NSPanel（同时**也**写一次剪贴板）
 ├─ .savePanel → NSSavePanel → MSImageEncoder → Data.write(.atomic)
 └─ .quickSave → MSFileExporter.uniqueURL → 同上
```

`.pin` 这一支带复制是有意的（`MSSession/MSSessionCoordinator.swift:424-428`）。注意贴图拿的是**⑤ 文档 + ② 的裁剪位图**，不是 ⑦ 的烘焙图：贴图要把矢量标注按屏幕分辨率重画，缩放时才不糊（§4.7）。

### 2.3 可变状态住在哪

| 状态 | 宿主 | 为什么在那 |
|---|---|---|
| `document`（标注层） | `MSOverlayView` 与 `MSPinView` 各持一份 | 值是 `Sendable` 结构体，跨 actor 传副本 ⇒ 贴图与导出永不互相同名共享 |
| `history`（撤销栈） | 同上，**与文档同生命周期** | 一张贴图进出编辑态不丢历史（`MSAnnotate/MSAnnotationHistory.swift:21-23`） |
| `selection` / `dragMode` / `draft` | 仅 `MSOverlayView` | 一次会话内的临时交互态 |
| `phase`（会话状态） | `MSSessionReducer`（纯值） | 状态可由事件序列重放、可无窗断言 |
| `frozenFrame` | `MSSessionCoordinator` | 释放点是"会话回到 idle"，不是"遮罩关窗"（`:572-582`） |
| `pins`（活窗列表） | `MSPinRegistry` | 靠 `willCloseNotification` 自动摘除（`MSPin/MSPinWindow.swift:572-577`） |
| `cached`（偏好） | `MSSettingsStore` + `NSLock` | 读多写少，跨模块只读 `current` |
| 静态回调表 `handlers` | `CarbonHotKeyService`（**static**） | Carbon 的 C 回调只能拿到无上下文指针，见 §4.4 的事故 |

## 3. 坐标系：全项目的结构骨架

`ADR-013` 说"跨空间换算必须调用显式函数"。落到代码上是三个空间、六个函数。

| 空间 | 原点 / y 方向 | 用在 |
|---|---|---|
| **视图（全局逻辑）** | AppKit 全局：主屏左下，y 向上 | `NSView` 绘制、鼠标事件、窗 frame |
| **显示器像素** | 该显示器左上，y 向下 | 采集帧内裁剪、尺寸读数 |
| **画布像素** | **选区**左上，y 向下 | 标注元素的 `points`、渲染器、导出 |

| 换算函数 | 方向 | 生产调用者 |
|---|---|---|
| `MSIntRect(flippedLogical:scale:)`（`MSCore/MSIntGeometry.swift:95`） | 视图矩形 → 像素矩形（两边各自取整） | **只有** `MSDisplay.pixelRect`（`MSCore/MSDisplay.swift:42`） |
| `MSDisplay.pixelRect(forLogical:)`（`MSCore/MSDisplay.swift:35`） | 全局逻辑矩形 → 本屏像素矩形 | 7 处：画布尺寸 `MSOverlay/MSOverlayView.swift:298`、拖动自检 `:417`、取样 `:496`、尺寸药丸 `:667`、代理裁剪 `MSSession/MSSessionCoordinator.swift:541`、帧内裁剪 `MSCore/MSCaptureFrame.swift:45`、`RegionCropper.crop`（`MSCapture/ScreenCapture.swift:114`） |
| `MSIntPoint.canvasPoint(of:in:scale:)`（`MSCore/MSIntGeometry.swift:52`） | 视图点 → 画布点 | 遮罩内三处：`docPoint`（`MSOverlay/MSOverlayView.swift:1109`）、选择工具命中（`:820`）、元素拖动（`:922`）——后两处**绕过 `docPoint` 直接调 Core**，口径一致但包装没被一致使用 |
| `MSIntPoint.viewPoint(in:scale:)`（`…:15`） | 画布点 → 视图点 | `MSOverlayView.editorFrame`（`:1019-1025`，文字输入框落位） |
| `MSIntPoint.documentDelta(selectionOld:to:scale:)`（`…:34`） | 选区变化 → 元素画布平移量 | `MSOverlayView.retargetElements`（`:270`） |
| `MSIntPoint.selectionDelta(fromDocument:scale:)`（`…:45`） | 反向（正逆成对，只在单测里对照） | `MSCoreTests/MSGeometryTests.swift` |

`MSCore/MSIntGeometry.swift:93-94` 那条注释解释了一个容易顺手改错的点：**宽 = round(maxX×scale) − round(minX×scale)**，不是 `round(width×scale)`。在 1.799x 这类非整数缩放上两者会差 1px，产生边缘渗色。

### 3.1 设备像素网格（为什么拖动会闪）

同一帧里"画布尺寸 / 取样矩形 / 元素平移量"三个量若各算一遍，能差 1 设备像素 ⇒ 背景被逐帧非整数重采样而标注按整数画 ⇒ 观感"框不动、边缘闪"（`V-070`/`E-110`）。代码上的对策是两条：

| 函数 | 作用 | 用在哪 |
|---|---|---|
| `MSIntPoint.snappedToPixelGrid(_:scale:)`（`MSCore/MSIntGeometry.swift:27`） | 把矩形四边吸到 1/scale 网格 | ①`canvasSize(for:)` 定画布（`MSOverlay/MSOverlayView.swift:297`）②`drawSelectionContents` 的**绘制目标**（`:375`，只吸绘制，不改选区本身） |
| `documentDelta` 内部先吸再取边差（`…:39`） | 保证"选区设备顶 + 元素画布 y"这条和为常量 | 拖动改选区 |

另一条对策是**基准**：拖动的位移一律从按下那一刻的矩形与元素表算总量，绝不在上一帧已取整的结果上继续加（`selectionDragBaseline`，`MSOverlay/MSOverlayView.swift:196`、`:267-268`、`:920-935`）。这条同时压住了两个缺陷：慢速拖动的累积漂移（`V-070`）和元素一拖就飘出选区（`V-071`/`E-112`）。

## 4. 模块逐个：类型与函数职责

### 4.1 `MSCore` — 值层

**`MSIntGeometry.swift`**

| 成员 | 作用 | 调用者 |
|---|---|---|
| `MSIntPoint` / `MSIntSize` / `MSIntRect` | 整数像素几何值类型；出现"小数坐标"的第一道墙 | 全项目 |
| `MSIntRect.midX/midY` | 整除取中（不做浮点中点） | `bounds` 并集、把手 |
| `MSIntRect.intersection/union/contains/insetBy` | 相交（nil 表示不相交）与并集 | 取样、裁剪、`contentBounds` |
| `MSIntPoint.snappedToPixelGrid` / `documentDelta` / `selectionDelta` / `canvasPoint` / `viewPoint` | 见 §3 | 见 §3 |

**`MSSelectionGeometry.swift`** — 选区的交互数学（纯函数，不开窗就能测）

| 成员 | 作用 | 调用者 |
|---|---|---|
| `Handle`（10 档：8 把手 + body + none） | 指针落在选区的哪一块 | `MSOverlayView.mouseDown` |
| `handle(at:of:hitTolerance:)`（`:18`） | 判定优先级：角 > 边 > 体；容差随 scale 放大 | `MSOverlay/MSOverlayView.swift:845` |
| `resized(by:handle:from:clampTo:lockedAspect:)`（`:65`） | 拖把手后的新矩形，**总是归一化**（拖过对角=翻转而非负尺寸） | `MSOverlay/MSOverlayView.swift:916` |
| `moved(by:rect:clampTo:)`（`:91`） | 平移 + 钳进边界 | 仅 `MSGeometryTests`；遮罩自己 `offsetBy` |
| `clamp(_:to:minimumSize:)`（`:118`） | 钳制 | `resized` 内部 |
| `snapTargets` / `snapped`（`:128`/`:138`） | 磁吸候选与就近吸附 | **未接进拖动**（§12） |

**`MSCaptureFrame.swift`** — 一帧的自述

| 成员 | 作用 |
|---|---|
| `pixelSize` / `logicalSize` | 像素与逻辑两套尺寸，恒由 `image` + `scale` 推 |
| `fullDisplay(_:display:)` | 整屏帧的构造糖，`sourcePixelRect` = 全屏 |
| `cropping(_:)`（像素，`:34`） | **只裁不采样**；同时把 `sourcePixelRect` 平移成新帧的来源 |
| `cropping(logicalRect:in:)`（`:44`） | 逻辑入口：先问 `MSDisplay.pixelRect`，再转相对本帧的像素矩形 |

**`MSImageSampler.swift`** — 颜色与取样

| 成员 | 作用 | 为什么这么写 |
|---|---|---|
| `MSColorRGBA` | 全项目唯一颜色类型（sRGB8 + Double alpha）；`hex()`/`rgbDescription`/`hslDescription`/`init?(hex:)` | 取样、标注、导出三处都要它 ⇒ 按 `ADR-012` 下沉 |
| `MSBitmap`（`:92`） | 把 `CGImage` 解成一份 RGBA8 缓冲，**一次解码服务多次取样** | 放大镜每次 `mouseMoved` 都取样 |
| `sample(pixelAt:)` / `average(in:)` / `rgbaBytes(in:)` | 单点取色、区域均值（放大镜均值档与马赛克）、紧凑字节拷贝（模糊） | — |
| `MSImageSampler.magnified(center:radius:zoom:)`（`:74`） | 近邻放大（`interpolationQuality = .none`） | 像素必须保持方形 |

**`MSKeyCombo.swift`** — 键位的可搬运表示 + **可绑定性判定**

| 成员 | 作用 | 调用者 |
|---|---|---|
| `functionKey(_:)`（`:24`） | 传 F 序号（1…12）而非 keyCode；越界 `preconditionFailure` | 测试与默认值 |
| `functionKeyCodes` / `keyNames` | 码表单源（门禁靠它检查"不许魔法数"） | `bindability`、`display` |
| `display`（`:45`） | `⌥⌘W` / `F1` | 状态栏 tooltip、设置窗、日志 |
| `bindability(keyCode:command:option:control:shift:)`（`:96`） | 五档判定（ok / functionKeyNeedsHint / needsModifier / reserved / unsupported） | `App/MSHotKeyEditor.swift:91` |

`:100` 那行注释记了一个真实误判：`keyCode 0` 是 A 键，写成"0 ⇒ 非法"会让 ⌘A 被拒。

**其余**

| 文件 | 内容 |
|---|---|
| `MSCommitIntent.swift` | 提交意图枚举（copy/pin/savePanel/quickSave/cancel）+ `MSErrors` + `MSImageFormat`。放在 Core 的理由：遮罩生产它、会话路由它、导出执行它 |
| `MSExternalSeams.swift` | `MSClock` / `MSPasteboardWriting` / `MSFileWriting` 三条接缝 + `DiskFileWriter`。剪贴板**只有一个 PNG 载荷**是有意的（`:23-25`） |
| `MSUpdate.swift` | `MSVersion`（补零逐段比较，`0.10.0 > 0.9.0`）、`MSUpdateManifest.decide`（校验和必须是 64 位十六进制，否则 `.malformed`）、`MSUpdateSource`（默认源 + `MACSHOT_UPDATE_URL` 覆盖）。**这个文件不发请求**，判据因此可离线 |
| `MSLog.swift` | `os.Logger` 按模块分类（10 个 category），一律 `privacy: .public`，因为字符串里只允许几何与标识符 |

### 4.2 `MSSettings` — 偏好与迁移

| 成员 | 作用 | 关键点 |
|---|---|---|
| `MSAppPreferences`（`:6`） | 一份全字段值类型 + `currentSchemaVersion = 5` | 字段**只追加**，改名/改义就是 schema break |
| `HotKeys` / `Export` / `AnnotationDefaults` / `CommitBehavior` / `Appearance` | 五组子结构 | `CommitBehavior.label`（菜单/设置用）与 `.shortLabel`（工具条 250pt 预算用）刻意分开 |
| `legacyExportDirectories`（`:23`） | 历史默认目录名单 | 迁移**认值不认版本**：只有等于历史默认的那条才回落，用户自填的一律不动 |
| `annotationStyle()`（`:97`） | 把偏好翻成 `MSAnnotationStyleSpec` | 用一个中立结构体跨边界，`MSAnnotate` 因此不必 import 本模块 |
| `MSSettingsStore.init`（`:127`） | 读盘 + 两条迁移 | `:140-144` 的"钉死在 4"与 `:148-152` 的"认值"是全项目最值得读的两段迁移代码 |
| `update(_:)`（`:165`） | 改内存 → 盖 schemaVersion → 落盘（`.atomic` + sortedKeys） | **每次写盘都把整份结构体连默认值 materialize 出去**——这正是"翻默认值对老用户不生效"的根因 |
| `resetToDefaults()`（`:177`） | 回落出厂值并落盘 | 供"默认值"判据 |

> 结构教训（`AGENTS.md` §0 已登记为纪律）：**改任何默认值，必须同批改"读旧文件的规则"**，否则只对全新用户生效。

### 4.3 `MSCapture` — 采集

| 成员 | 作用 | 调用者 |
|---|---|---|
| `protocol ScreenCapturing`（`:28`） | 唯一采集入口 `freeze(display:) async throws -> MSCaptureFrame` | 会话；测试用 `MSFakeCapturer` |
| `ScreenCaptureKitCapturer.freeze`（`:39`） | ①只取 `content.displays`（`excludingDesktopWindows(true)` ⇒ 不枚举桌面窗口）②按 `display.pixelSize` 配尺寸 ③`SCScreenshotManager.captureImage` ④空帧/均匀黑帧 → `.permissionMissing` | 会话（后端启动时定） |
| `CoreGraphicsCapturer`（`:81`） | `CGDisplayCreateImage` 回落 | 当前不被选中，见 `decide` |
| `CaptureBackendSelector.decide/decide(forced:)`（`:95`） | **启动定一次、会话内永不切换**，避免"有时行有时不行" | `App/main.swift:41`、`App/MSAppDelegate.swift:79` |
| `MSCaptureError.isPermissionDenied`（`:10`） | 把 SCK 的 `SCStreamErrorDomain -3801` 归类成"权限被拒" | `freeze` 的 catch、会话 |
| `RegionCropper.crop(_:logicalSelection:in:)`（`:113`） | 唯一裁剪入口，强制走 `pixelRect` | 会话提交 |
| `PermissionProbe.screenRecording/requestScreenRecording`（`:130`/`:136`） | `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` | 状态栏权限行、会话 |
| `MSCaptureDiagnostics.isDegenerate`（`:146`） | 五点全等 **且** 接近纯黑 ⇒ 才判"没权限" | 会话、`--probe-capture` |
| `MSDisplayInventory.current/display(under:in:)/desktopLogicalFrame`（`:9`/`:24`/`:29`） | 读 `NSScreen` 造 `MSDisplay` 快照 | 会话（每会话一次） |

`:142-144` 的注释是一次误诊的现场记录：只看"五点全等"会把"白底文档 + 白边"误判成缺权限，而且一旦判错，后续每次截图都开不了。加"且近黑"这一半，才是无权限时系统给的真形状。

### 4.4 `MSHotKey` — Carbon 全局热键

结构上只有四类，但回调链有一条硬约束：

```
用户按键 → Carbon 事件 → sharedHandler（C 函数指针，拿不到 Swift 上下文）
        → CarbonHotKeyService.dispatch(id:)（static 表查回调）
        → DispatchQueue.main.async(handler)
        → App 层闭包 → Task { @MainActor coordinator.handle(id) }
```

| 成员 | 作用 | 关键点 |
|---|---|---|
| `MSHotKeyID`（`:5`） | snip=1 / pinClipboard=2 / fullScreen=3，**数值进 EventHotKeyID** | 值不能改（与已注册项共存） |
| `MSRegistrationResult.init(_:)`（`:14`） | 把 `OSStatus` 归成 ok / alreadyTaken(-9878) / failed | 数值比对而非用常量符号（类型不一致） |
| `sharedHandler`（`:39`）+ `handlers`（`:38`，**static**） | C 回调 → 静态表 | 见下面的事故 |
| `register(_:id:handler:)`（`:66`） | 顺序：**先 `unregister` 再 `setHandler`** | 反过来就是把刚挂的回调擦掉 ⇒ "注册成功却按了没反应"（`E-089`） |
| `unregister` / `unregisterAll`（`:95`/`:102`） | 拆注册**同时**擦回调表 | 少一步就留下"注册已拆、回调还在表里"的不对称 |
| `rebind(to:previous:handlers:)`（`:115`） | 全量换绑，任一失败回滚旧集 | `MSAppDelegate` 走的是逐条 `register` + 失败装回，语义相同 |
| `dispatch(id:)`（`:147`，`static internal`） | 测试入口：模拟"Carbon 回调进来了" | 否则判据永远差一手 |
| `carbonModifiers`（`:162`） | 转 Carbon 掩码 | 刻意不用 `NSEvent.ModifierFlags`（rawValue 不同） |

### 4.5 `MSAnnotate` — 标注模型与渲染（无 AppKit）

**`MSAnnotationDocument.swift`**

| 成员 | 作用 | 结构意义 |
|---|---|---|
| `MSAnnotationStyle`（`:7`） | 描边/填充/线宽/圆角/虚线/箭头帽/字号/粗体/模糊种类与半径 | **每个元素各存一份** ⇒ 改当前样式不会重涂已画的（`FR-ANN-003`） |
| `MSAnnotationKind`（`:43`） | 12 种（9 种首批 + line/spotlight/crop） | rawValue 是永久契约（`ADR-009`）；`spotlight`/`crop` 渲染器不画 |
| `MSAnnotationElement`（`:55`） | `id`+`kind`+`points`+`style`+`z`+`text`+`variant`+`boundsOverride` | `points` 恒为**画布像素 y-down**（`:58-60`）⇒ 同一文档在任何 scale 上画得一样 |
| `translated(by:)`（`:71`） | 平移所有锚点（含 `boundsOverride`） | 自己**不做任何换算**，位移只能由 `documentDelta` 给 |
| `MSAnnotationDocument`（`:97`） | `canvasSize` 不可变 + `elements` + `currentStyle` + `badgeCounter` | 值类型 `Sendable`：贴图与导出各拿副本，永不互相同步 |
| `append`（`:122`） | 自动分配 z = max+1；空文本 badge 自动填号 | — |
| `sortedElements`（`:120`） | 按 z 升序 = 绘制顺序 | 渲染器、命中、橡皮擦都读它 |
| `raise/lower`（`:137`/`:143`） | z ±1（越界即不动） | `⌘]` / `⌘[` |
| `contentBounds`（`:155`） | 元素外接并集（按线宽外溢）∩ 画布 | 未来的"裁到内容" |

**`MSAnnotationRenderer.swift`** — 唯一的一条"文档 → 像素"

| 成员 | 作用 | 关键点 |
|---|---|---|
| `MSRenderIntent`（`:9`） | `preview` / `pin` / `export` | 三种意图必须产同一套像素，这条不变量挡掉"屏上粉、导出黑" |
| `render(_:source:intent:)`（`:22`） | 建 sRGB/premultipliedLast 位图上下文 → 画源 → 画元素 → 出图 | 输出尺寸恒等 `canvasSize`；`interpolationQuality = .none` |
| `renderElements(of:into:source:canvas:intent:)`（`:43`） | **只画元素层**，供调用方自配 CTM | 贴图靠它把位图缩放、矢量按原生分辨率重画 |
| `draw(_:…)`（`:57`） | 按 kind 分支绘制 | 进函数时 CTM 已是 y-down 文档空间（`:48-49` 翻的） |
| `drawArrowHead`（`:136`） | 箭头帽：单/双/三角，尺寸跟线宽 | — |
| `MSImageOps.blurred`（`:212`） | `pixelate`=整数块均值；`gaussian`=两次盒式近似 | 手写而非 `CIFilter`：无依赖 + 字节可复现，快照测试要的就是这个 |
| `font(_:bold:)` / `line(…)`（`:156`/`:168`） | CoreText 取系统字体、造 `CTLine` | `NSAttributedString.Key.font` 在 AppKit ⇒ 本模块不许用 |
| `drawText`（`:175`） | 逐行落笔，基线 = 行框顶 + fontSize | `:183-187` 的翻正只做一次，写反过 ⇒ 文字整段出画布 |
| `drawTextCentered`（`:194`） | 光学包围盒对中（badge 里的数字） | — |

**`MSAnnotationGeometry.swift`** — 命中与外接

| 成员 | 作用 |
|---|---|
| `hitTolerance(for:)`（`:10`） | `max(4, lineWidth+2)`，1px 线也点得到 |
| `bounds(of:)`（`:14`） | badge 按半径、text 按"最长行 × 字号 × 0.62"估算、其余取锚点并集；`boundsOverride` 优先 |
| `badgeRadius(for:)`（`:39`） | 半径随位数增，1→99 视觉同大 |
| `hitTest(_:element:extraTolerance:)`（`:49`） | 折线类=到路径距离；矩形/椭圆/模糊类=**未填充只命中轮廓、填充了内部也算**；文字/badge=外接盒 |
| `distanceToPath`（`:67`） | 逐段点到线段距离取最小 |
| `handles(of:)`（`:84`） | 8 个把手（nw,n,ne,e,se,s,sw,w） |
| `translated`（`:92`） | 整数版平移（与 `MSAnnotationElement.translated` 语义相同、取整口径不同：这里先 round 位移） |
| `scaled(_:factor:about:)`（`:104`） | 等比缩放（留给 FR-ANN-012，当前无调用者） |

**`MSAnnotationHistory.swift`** — 命令式撤销（非快照式）

| 成员 | 作用 |
|---|---|
| `MSAnnotationCommand`（`:6`） | insert / remove / replace / currentStyle / badgeCounter / **indirect composite** |
| `compose(_:)`（`:14`） | 单子步直接返回、多子步合成一条、全空返回 nil |
| `apply(_:to:)`（`:37`） | 执行 + 入栈 + 清 redo，深度 200 |
| `undo` / `redo`（`:46`/`:53`） | 两栈互推 |
| `MSDragRecorder`（`:83`） | 把一次拖拽的上百次更新收成**一条** `replace`；`command` 在没真动过时返回 nil |

**`MSAnnotationToolbar.swift`** — 工具条的**度量单源**（摆在哪由表面自定）

| 成员 | 作用 | 为什么在这 |
|---|---|---|
| 常量（`:10-19`） | 格 26 / 缝 2 / 高 34 / 内边 4 / 色点 14 / 色距 18 / 动作区 250 | 遮罩与贴图共用同一条工具条，而 `MSPin` 不许 import `MSOverlay` |
| `naturalWidth` / `showsActions`（`:22`/`:29`） | 自然宽与"要不要收掉键位提示" | 收的顺序定死：先收提示文字，**不收工具** |
| `boxes(rect:itemCount:colorCount:)`（`:36`） | 工具格与色格坐标 | **绘制与命中读同一份** |
| `BarAction`（`:54`） | commit/copy/save/cancel + 各自 `hint` 与 `label(verb:)` | 提交格的动词跟随设置项 |
| `textWidth` / `isWide`（`:76`/`:80`） | CJK 按 1em、其他按 0.6em 估宽 | 近似值只用来定格子；绘制与命中同源 ⇒ 只会更宽不会点不到 |
| `actionBoxes(rect:labels:)`（`:89`） | 从右往左排动作格 | 总宽不得超 `actionWidth`（`ToolbarGeometryTests` 钉住） |
| `flow(toolCount:colorCount:maxWidth:maxHeight:)`（`:108`） | 多行布局，色板独占最后一行；放不下返回 nil | 贴图窄窗用；nil 必须有兜底（字母选工具） |

**`MSTool.swift` / `MSAnnotationPalette.swift` / `MSAnnotationIcons.swift`**

| 成员 | 作用 |
|---|---|
| `MSTool`（11 档）+ `letter` | 工具 ↔ 字母（真源 `design/keymap.md` §3）。`select/rect(M)/ellipse(O)/arrow(A)/polyline(L)/highlighter(H)/pen(P)/blur(B)/badge(N)/eraser(E)/text(T)` |
| `annotationKind` | 工具 → 文档 kind（select=nil；highlighter 与 pen 都映到 `.freehand`，靠 `variant` 分） |
| `isClickAction` | badge/eraser＝单击成事，不进拖拽草稿 |
| `MSAnnotationPalette.swatches/toolbar` | 8 色真源，工具条露前 6 |
| `MSAnnotationIconTable.symbolName(for:)` / `polylinePath(in:)` | 工具 → SF Symbol 名（折线没有符号 ⇒ 自绘路径），**纯 CG，不 import AppKit** |

### 4.6 `MSOverlay` — 遮罩

**`MSOverlayView.swift` 里的 `OverlayChrome`（`:10-41`）** — 常驻控件几何

| 成员 | 作用 |
|---|---|
| `cancelVisual=28` / `cancelHit=44` / `margin=14` | **命中区永远大于视觉区** |
| `cancelHitRect` / `cancelVisualRect` / `cancelPaintRect` | 三个矩形同源；`cancelPaintRect` 故意等于视觉矩形（`:27-29` 记了"多翻一次 y ⇒ 看得见在左下、点得到在左上"的事故） |
| `cancelHintOrigin` | 提示条跟着 ✕ 走 |
| `scrimAlpha(isDark:)` | 0.45/0.55，数值真源是设计 token |

**`MSOverlayDelegate`（`:50-69`）** — 视图唯一对外说话的方式（9 个方法）：`selectionDidChange` / `didDropAnnotations` / `didRequest` / `overlayDidCancel` / `drawingPhaseDidChange` / `elementCount` / `didPickColor` / `cropOfViewRect` / `overlayPreferences`。生产方全在视图，消费方只有会话。

**`MSOverlayWindow`（`:76-157`）**

| 成员 | 作用 | 关键点 |
|---|---|---|
| `init(display:frame:)`（`:80`） | borderless、透明、`statusBar+1`、可跨 Space、`acceptsMouseMovedEvents` | level 比贴图（statusBar）高一级 ⇒ 遮罩压住贴图 |
| `canBecomeKey=true` / `canBecomeMain=false`（`:97-98`） | 要键盘、不要成为主窗 | — |
| `present()`（`:105`） | activate → makeKeyAndOrderFront → makeFirstResponder → 装本地键监视器 → 请键 | 顺序不可换（`:102-104`） |
| `claimKey(attempt:)`（`:117`） | `NSApp.activate` 是异步的 ⇒ 6 次退避重试，每次打 `key=`/`responder=` | 没有这段就是"Esc 完全没反应" |
| `installKeyMonitor()`（`:137`） | 本地监视器：responder 链断了也还能收键 | 与 `keyDown` 双通路，两条都要通 |
| `teardown()`（`:147`） | 必须摘监视器，否则它吃掉之后所有按键 | 全局监视器已因权限收缩删除 |

**`MSOverlayView`（`:161-1262`）** — 全项目最大的一份，结构上分七段：

*状态与换算*

| 成员 | 作用 |
|---|---|
| `selection` / `tool` / `draft` / `selectedID` / `dragMode` / `document` / `history` | 交互核心状态 |
| `selectionDragBaseline`（`:196`） | 拖动基准（矩形 + 元素表），见 §3.1 |
| `globalSelection`（`:235`） | 视图选区 + 窗原点 = 全局逻辑选区，**会话裁剪用的就是它** |
| `setSelection(_:)`（`:240`） | 唯一改选区的入口：先报"选区变了"（此时 `hasElements` 还是改前真值）→ 保留/迁移元素或换文档 → 清合成缓存 → 重绘 |
| `retargetElements(from:to:)`（`:263`） | 改选区时：**屏幕位置还在新选区里的原地保留，跑出去的才清**，且合成一条撤销记录 |
| `canvasSize(for:)`（`:290`） | 画布尺寸 = 本帧取样用的那个设备矩形（先吸网格） |
| `ensureDocument(for:)`（`:308`） | 尺寸没变就复用文档（否则每帧丢标注） |
| `docPoint(_:in:)`（`:1108`） | 视图点 → 画布点（转调 Core） |
| `translation(for:from:to:)`（`:1112`） | 把手 → 位移向量（把 y-up 的"顶"当 maxY） |

*绘制*

| 成员 | 作用 | 顺序/坑 |
|---|---|---|
| `draw(_:)`（`:316`） | 冻帧 → 暗化 → 选区内容 → 选中框 → 把手 → 工具条 → 读数 →（自检）→ 放大镜 → ✕ | 工具条**先算**才能给读数让位（同帧真值，不用上一帧 layout） |
| 暗化用**四条带**而非偶奇挖洞（`:325-331`） | 只有变化的带会重绘 | — |
| `drawSelectionContents`（`:372`） | 绘制目标吸网格 → 取样 → 取合成图 → 画 → 叠草稿 → 自检 | `NFR-011`：所见=所存 |
| `compositedCrop(for:)`（`:476`） | 元素层+底图的合成缓存，键=(元素表, 源尺寸) | 拖草稿期间**不该重烤**；`compositeBakeCount`（`:491`）就是这条的读数 |
| `drawDraft`（`:451`） | 矢量层实时上屏 | 模糊例外：只画虚线轮廓，松手才糊（每帧整块 CPU 模糊会真掉帧） |
| `drawElementSelection`（`:512`） | 选中元素的蓝色虚线盒（文档坐标 → 视图） | — |
| `drawToolbar`（`:696`） | 背景 → 工具格（图标失败回落字母）→ 色板 → 动作格 | "格子在、里面空"是不许出现的形态 |
| `drawReadout`（`:666`） | 尺寸药丸 `W×H @2x`，落位问 `MSOverlayToolbar.readoutOrigin` | 记 `readoutRect` 供自检 |
| `drawCancelButton`（`:351`） | ✕ + 提示条 | 位置全问 `OverlayChrome`，本函数不做换算 |
| `drawHint`（`:683`） | 无选区时的屏底提示 | 硬编码宽度 `midX - 178` |

*放大镜（模型在 `MSOverlayLoupe.swift`）*

| 成员 | 作用 |
|---|---|
| `loupeAnchor` / `loupeForced` / `loupeFormat` / `isDraggingSelection` | 状态；`mouseMoved` 与 `mouseDragged` 都更新锚点（拖拽期系统不发 moved） |
| `loupePixel` / `loupeColor` | 取样点与取样色（`lazy loupeBitmap` 一次解码服务整场会话） |
| `isLoupeVisible`（`:574`） | `(拖选中 && 开关) 或 ⌥` |
| `drawLoupe`（`:593`） | 外框 → 近邻图 → 17×17 网格 → 中心格描 accent → 读数条 |
| `MSLoupeModel.rect`（`MSOverlay/MSOverlayLoupe.swift:31`） | 四象限避让（右下→左下→右上→左上），都不行才夹回屏内 |
| `MSLoupeModel.gridRect` / `centerCell`（`:52`/`:58`） | 网格与中心格**同一来源**（两边各算会把近邻图拉成非整数倍，取色就不准） |
| `MSLoupeModel.pixel`（`:86`） | 视图点 → 帧像素（显式翻 y + 钳边） |
| `MSLoupeModel.readout/copyString`（`:67`/`:77`） | 读数串与 `C` 复制的串（只角色值，不带坐标） |

*命中与事件*

| 成员 | 作用 |
|---|---|
| `ToolbarHit` + `toolbarHit(_:)`（`:741-752`） | 四档：tool / color / action / **blank**（色格容差 ±3） |
| `actionLabels` / `actionBoxes` / `visibleActionBoxes`（`:756-770`） | 动作格几何；**没画就不许能点** |
| `mouseDown`（`:783`） | 路由优先级见 §8 |
| `mouseDragged`（`:895`） | 五支：newSize(⌥=正方形) / move / resize / moveElement / draw |
| `mouseUp`（`:951`） | 元素拖动→一条撤销；草稿→按尺寸阈值入文档；无草稿且选区 <4pt→清空 |
| `elementAt(_:)`（`:862`） | 命中的**最上层**（z 最大）元素 |
| `performClickAction(at:)`（`:870`） | badge=插入+计数自增打包成一条；eraser=删命中最上层 |
| `handleKey(_:)`（`:1153`） | 键位总路由（见 §8）；编辑态先走 `handleTextKey` |
| `undo` / `redo` / `deleteSelectedOrLast` / `changeLayer`（`:1220-1253`） | 编辑动作 |
| `applyDefaults(_:)`（`:1127`） | 把设置里的样式装进视图（会话建窗后立刻调） |
| `annotationDocument`（`:1257`） | 交给会话导出的文档（没画也返回空文档 ⇒ 裁剪仍成立） |
| `*ForProbe`（`:555-573`、`:773`） | 探针/测试只读口：草稿种类、走了哪条拖拽支路、已提交元素数、**画出来的**动作格 |

**文字输入子态（`:999-1103`）**：`TextEditing` 记 `elementID`（nil=新建）/`anchor`/`before`/`textView`；`editorFrame(anchor:selection:scale:fontSize:)` 把画布锚点换成视图矩形（框**向下**长，因为 y-up）；`beginTextEditing` 造 `NSTextView` 并抢焦点；`commitTextEditing` 空文本不入记录；`abortTextEditing` 只退子态、**不退整个遮罩**。

**`MSStatusGlyph.swift`**：`image()` 直接把菜单栏 SVG 当矢量资源用（实测 AppKit 读得动）；读不到返回 nil，调用方回落文字 ✂；`inkCoverage(of:)` 量"画得出墨"的比例，把"素材能加载"和"真画得出来"分开证。

### 4.7 `MSPin` — 贴图

| 成员 | 作用 | 关键点 |
|---|---|---|
| `MSPinContent`（`:11`） | `document`+`source`+`scale`+`sourcePixelRect`；`bitmap(_:scale:)` 把外来位图立刻包成空文档 | 只有一条渲染路径 |
| `logicalSize`（`:27`） | 文档像素 / scale | 窗尺寸由它推 |
| `MSPinLevel`（`:35`） | 候选档位表（floating/statusBar/statusBar+1/popUpMenu），`current = .statusBar` | 升序是 AppKit 事实不是偏好 |
| `MSPinGlow`（`:64`） | 留白 10pt、三层环 (9/.07)(5/.15)(2/.30)、1pt 高光 | **只活在 chrome 层**：导出走渲染器，不经过视图绘制 ⇒ 加光晕不动任何内容像素 |
| `MSPinWindow.init`（`:81`） | `NSPanel` + borderless + **nonactivatingPanel**、`hidesOnDeactivate=false`、`canJoinAllSpaces/fullScreenAuxiliary/stationary/ignoresCycle`、`isMovableByWindowBackground=true` | 不夺焦点是贴图的基本属性 |
| `pinDidRequestToggleEdit`（`:116`） | 切编辑态时**同时**翻转 `isMovableByWindowBackground` | 拖窗 vs 拖标注互斥 |
| `markDirty()` / `hasExported`（`:127`/`:79`） | 任何编辑让"未导出"徽章回来 | D-04 的代价要在屏上说实话 |
| `imageRect`（`:163`） | 图片真正占的矩形（四周留白，底部让给工具带） | **位图/矢量层/工具带/徽章/docPoint 全从它取** |
| `zoom` didSet（`:171`） | `resizeWindow()` 先，`applyStrip()` 后 | strip 读 `bounds.width`，顺序反了用旧宽 |
| `resizeWindow()`（`:193`） | 顶边不动地长缩 | — |
| `draw(_:)`（`:205`） | ①位图（zoom>1 关插值 ⇒ 看得见像素块）②矢量层（按 `imageRect.width/docW` 缩放 CTM，笔画重绘不失真）③编辑态 chrome + 工具带 ④徽章 ⑤**光晕最后画** | ②就是 D-04 的可见证据 |
| `drawGlow`（`:236`） | 偶奇裁剪（整窗 − 图片）保证一像素都不吃画面 | 判据靠"画在后面"才有牙齿 |
| `applyStrip()`（`:284`） | 编辑态工具带高度 = min(160, 图片高) 预算内 `flow` 的结果；放不下就 0 | 11-17 走过折行方案，实测盖掉 75% 画面 ⇒ 改撑高窗 |
| `pinToolbarTools`（`:275`） | 排除 `text` | 这里没有 field editor，接进去只会落一个空文本元素 |
| `computeEditToolbar`（`:307`） | `flow` 的局部格子平移到工具带 | 与 `drawEditToolbar` 共用；`editToolbarLayout` 供命中 |
| `drawEditToolbar`（`:324`） | 画得出格子就画格子，否则画"按字母选工具"的提示 | 兜底形态必须是**说得出**的 |
| `drawBadge`（`:372`） | `120%`、`45%`、`未导出` 三段拼一条药丸 | — |
| `mouseDown`（`:397`） | 工具带 → 画布（点击型工具→`performClickAction`；否则起 `draft`）→ 非编辑态交回 `super`（拖窗） | — |
| `docPoint(_:)`（`:498`） | 视图点 → 画布点，**基准是 `imageRect` 不是 bounds** | 用 bounds 会把画面纵向拉长 ⇒ "越靠下越偏" |
| `scrollWheel`（`:512`） | 滚=缩放（0.05…8），⌘滚=透明度 | — |
| `keyDown`（`:521`） | 编辑态先认字母选工具与 Enter/Esc 退出；再认 ⌘C/⌘S/⌘W/E/⌘Z/⌘0 | 用 `if + [53,36,76].contains` 而不是 switch（门禁禁 `default: break`） |
| `bakedImage()`（`:491`） | 导出/复制用的烘焙图 | 与窗无关 ⇒ 工具带不可能污染导出 |
| `MSPinRegistry.open`（`:568`） | 建窗 + 挂 `willCloseNotification` 自动摘除 | 注册表是"关闭所有贴图"的唯一依据 |
| `releaseMemoryIfEmpty()`（`:587`） | 空表时 `malloc_zone_pressure_relief(nil, 0)` | RSS 停在高位是分配器缓存不是泄漏（`E-072` 实测：压一次从 +32.9MB 回到 +1.9MB） |
| `reanchorAll(to:)`（`:609`） | 显示器变了把跑出去的贴图捞回可见区 | — |

### 4.8 `MSExport`

| 成员 | 作用 | 关键点 |
|---|---|---|
| `MSBitmapBaker.bake`（`:51`） | 文档 → CGImage（`intent = .export`） | 单向烘焙：导出不携带文档 |
| `MSImageEncoder.dpi(scale:)`（`:60`） | `72 × scale` | 接收方按逻辑尺寸放图 |
| `png/tiff/jpeg/encode`（`:62-83`） | ImageIO 编码，DPI 写进 `kCGImagePropertyDPIWidth/Height` | 不手写 pHYs chunk |
| `reportedDPI(of:)`（`:86`） | 读回文件自报的 DPI | 判据要的是"文件真说了这句话" |
| `MSClipboardWriter.write`（`:115`） | 编码 → 一次写 → **比对 `changeCount`** | 没变＝别人抢了剪贴板，返回 false 而不是假装成功 |
| `writeText(_:)`（`:133`） | 放大镜取色 `C` 的纯文本写 | 同一条接缝、同样查 changeCount |
| `MSNamingTemplate.expand`（`:17`） | 12 个 `{变量}` 替换 + 把 `/ \ :` 削成 `-` | 变量表真源在架构文档 |
| `MSFileExporter.uniqueURL`（`:185`） | 模板里没有 `{index}` 也要防撞：追加 `-NNN` | 一秒内连存 10 次要得 10 个文件 |
| `save(_:)`（`:199`） | 编码 → 写 → 返回 `.written/.failed` | 结果可断言，而不是看副作用 |

### 4.9 `MSSession` — 结构上最该先读的一个模块

```
MSSessionReducer（纯 struct，可无窗重放）        MSSessionCoordinator（@MainActor，唯一持活对象）
  handle(event) -> [effect]                        run(event) { for effect in reducer.handle … }
                                                   perform(effect)  ← 穷举，无 default
```

| 类型 | 作用 |
|---|---|
| `MSSessionPhase`（`:12`） | `idle/frozen/selecting/editing/committing/failed/gate` |
| `MSSessionEvent`（`:14`） | 11 档输入（热键、权限、遮罩出现、选区变化、丢了几条标注、绘制起止、元素数、取色、提交、效果完成、采集失败） |
| `MSSessionEffect`（`:33`） | 11 档输出 |
| `MSSessionCopy`（`:52`） | **给用户看的文案只有一个家**（范围外标注被清掉的提示） |
| `MSSessionReducer.handle`（`:69`） | 迁移表；落不到任何一行的走 `default`（`:162-170`）＝**记日志 + 原地不动**，绝不发明迁移 |
| `coordinator.run(_:)`（`:228`） | 执行效果；回到 idle 才释放 `frozenFrame` |
| `startSnip`（`:296`） | 快照显示器 → 记前台 app → `run(.hotKeyPressed)` → 异步 freeze → 建窗 → `applyDefaults` + 明暗 + 放大镜档 → present → `run(.overlayShown)` |
| `handleFreezeFailure`（`:271`） | **权限失败**与**其它采集失败**分两支；且"系统说已授权"时不许开权限窗，改说"这一帧是空画面" |
| `requestPermissionOnce`（`:236`） | 每进程只申请一次（被拒过一次系统就不再弹框） |
| `commit(intent:selection:document:)`（`:378`） | 裁 → 烘 → 按 intent 分四出口；`.pin` 额外写剪贴板 |
| `perform(_:)`（`:617`） | 效果分发器；`.freeze`/`.showOverlay`/`.bakeAndCopy`/`.openPin`/`.saveToFile` 显式声明"由启动流/提交流执行"而不是静默丢弃 |
| `cancelSession`（`:549`） | 幂等；即使状态机拒绝该迁移也强制收窗（卡住比丢一张截图严重） |
| `reapplyChromePreferences`（`:503`） | 设置改了 → **已开着的遮罩立刻跟着变** |
| `applyChromeAppearance`（`:516`） | `appearance` → `NSAppearance` 挂窗（视图只读 `effectiveAppearance`，不自己判断明暗） |
| `makePinMenu`（`:650`） | 贴图右键菜单三行，`keyEquivalent` 恒空串 |

> 两条被事故钉住的顺序（读代码时最值得停下来想的两个细节）：
> ① `overlay(_:didRequest:)`（`:487`）先 `run(.commitRequested)`（效果里含关窗）再 `commit()` ⇒ `closeOverlay` **不许**清 `frozenFrame`，否则提交路径静默空转（`E-063`，注释在 `:578-581`）。
> ② 委托回调里**不许**调 `finishEffects()`（它的语义是"会话结束"），否则选区一变遮罩就消失（`:472-476`）。

### 4.10 `MSTestSupport`

| 成员 | 作用 |
|---|---|
| `MSTestCard.image/`display` | 已知像素卡（左半红、右上白、右下黑、中线硬边）+ 一台 scale=2 的假屏；像素断言有外部裁判 |
| `MSFakeCapturer` | 返回测试卡，可注入 `failure`，记 `callCount` |
| `MSFakePasteboard` | 记 `writtenPNG`/`writtenText`/`writeCount`，可拒绝写 |
| `MSFakeHotKeyService` | 记注册表，`trigger(id)` 让测试"按键" |
| `MSFakeFileWriter` | 记 `writes`，可预置已存在路径、可失败 |
| `MSSamples` | 常用元素与文档 |
| `MSSessionTestSupport.drive` | 喂一串事件，返回终相位与全部效果 |

### 4.11 `App/` — 装配层

| 文件 | 内容 |
|---|---|
| `main.swift` | 顶部一串 `if CommandLine…` 把同一份二进制当十几个探针用；最后一个分支才是正常启动（`:236-240`）。**每个探针都是"起 app → 定时触发 delegate 的一个方法 → 写 /tmp → exit"** |
| `MSAppDelegate.swift` | 装配（`:77-95`）；热键注册与改绑回滚（`:106-152`）；状态栏左键截图/右键菜单（`:158-193`、`:782-797`）；权限行**持引用不按键查**（`:195-204`）；失焦即收遮罩（`:800-809`）；权限引导窗（`:827-878`）；设置窗（`:1022-1120`）；登录项（`:1141-1153`）；toast 装配（`:1243-1247`）；小构造器（`:1251-1272`）；`ButtonBox`（`:1276-1283`，按钮目标持有者，否则闭包被 ARC 收掉）；**十几个 `probe*` 方法** |
| `MSAppDelegate` 顶部两个类 | `MSSystemPasteboard`（`:16`，一次 `clearContents` + 一次 `writeObjects`）与 `MSPNGItem`（`:38`，只声明 `public.png`） |
| `MSHotKeyEditor.swift` | 录制型改绑控件：录制前**先注销旧注册**（`:75`）、失败立刻装回（`:99`）、判定与文案来自 `MSCore` 纯函数 |
| `MSToast.swift` | 单例面板复用（不叠第三条）、层级 statusBar+1、**每次 show 都重排隐藏计时**（`:75-87`）、两个 `*ForProbe` 只读口 |
| `MSUpdater.swift` | 全项目**唯一**出网文件：`check`（拉清单 → `decide`）、`download`（字节数 + SHA-256 双校验，不符**删文件**返回 nil）、`sha256`（分块）、`present`（NSAlert 三键）、`describe`（日志短标签，不含 URL 参数） |
| `MSTcc.swift` | `tccutil reset ScreenCapture <bundleID>`，参数全常量、不拼用户输入 |
| `MSChromeDump.swift` | `--dump-chrome`：造棋盘底 → 建真遮罩窗 → 摆选区 →（`loupe`/`draft` 档喂合成事件）→ 离屏自绘成 PNG |

## 5. 十二条调用链（照这个顺序读源码最快）

### 5.1 冷启动

```
App/main.swift:236  NSApplication + setActivationPolicy(.accessory)
 → App/MSAppDelegate.swift:77  applicationDidFinishLaunching
    ├─ :79  CaptureBackendSelector.decide() → :80 makeCapturer（**启动定一次**）
    ├─ :81  MSSessionCoordinator(capturer:, preferences: settings, pins:, clipboard:)
    ├─ :83  coordinator.onToast  = { lastToast = $0; showToast($0) }
    ├─ :84  coordinator.onNeedsPermission = presentPermissionGate
    ├─ :86  buildStatusItem()          ← 左键直接截图、右键菜单、权限行
    ├─ :87  registerHotKeys()          ← combos(from:) → CarbonHotKeyService.register
    ├─ :88  observeDisplays()          ← 屏参变化 → pins.reanchorAll + 刷新权限行
    └─ :89  observeResignActive()      ← 失焦且遮罩开着 → cancelSession（不留吃点击的窗）
```

### 5.2 F1 → 冻结 → 遮罩出现

```
Carbon sharedHandler → dispatch(id:) → main.async → App/MSAppDelegate.swift:139 的闭包
 → MSSession/MSSessionCoordinator.swift:219 handle(.snip) → :296 startSnip()
    ├─ :304 displaySnapshot = MSDisplayInventory.current()        （会话内不再重读）
    ├─ :305 display(under: NSEvent.mouseLocation)
    ├─ :314 PermissionProbe.screenRecording()  ← **只记日志，绝不早退**（早退会让 TCC 列表里永远没有 MacShot）
    ├─ :319 run(.hotKeyPressed(.snip)) → reducer: idle→frozen，effects [.freeze,.showOverlay]
    └─ Task {
         ├─ capturer.freeze(display:)          MSCapture/ScreenCapture.swift:39
         ├─ MSOverlayWindow(display:frame:)    MSOverlay/MSOverlayView.swift:80
         ├─ applyDefaults(annotationStyle())   :1127   ← 设置里的样式进视图
         ├─ applyChromeAppearance + autoLoupeWhileDragging  :516 / :331
         ├─ window.present() → claimKey 重试    :105 / :117
         └─ run(.overlayShown) → frozen→selecting
       }
```

### 5.3 拖出一个新选区（每帧）

```
mouseDown :783 →（✕ → 工具条 → 文字态 → 文字工具 → 点击型工具 → 选择工具 → 绘制工具）→ 落到 :839
 :841 isDraggingSelection = true            ← 只有真"拖选区"才置位，画标注不弹放大镜
 :848 dragMode = .newSize(anchor:) ; setSelection(0×0)
mouseDragged :895 → .newSize :901 → 归一化矩形（⌥ = 正方形）→ setSelection :240
    ├─ retargetElements :263（有元素时）或 ensureDocument :308
    ├─ canvasSize(for:) :290（吸网格后问 pixelRect）
    └─ delegate.selectionDidChange → coordinator :477 → run(.selectionChanged)
mouseUp :951 → isDraggingSelection=false ; 基线清空 ; <4pt 则 setSelection(nil)
draw :316 → 四带暗化 → drawSelectionContents :372 → 把手/工具条/读数
```

### 5.4 画一条标注（拖拽期就要看见）

```
mouseDown :832 → dragMode=.draw ; draft=MSAnnotationElement(points:[p,p]) ; delegate.drawingPhaseDidChange(.began)
mouseDragged :936 → docPoint :1108 →（自由曲线追加点，曼哈顿距离 >2 才加）/（两点类替换终点）→ needsDisplay
draw → drawSelectionContents :385 → drawDraft :451
        ├─ 矢量类：临时造 doc(elements:[draft]) → renderer.renderElements（与提交后同一条路径）
        └─ blur：只画虚线框（每帧整块 CPU 模糊会掉帧）
mouseUp :967 → draft 落定 → history.apply(.insert) → document=doc ; cachedComposite=nil
coordinator :495 drawingPhaseDidChange(.ended(count)) → run(.elementCountChanged) → hasElements=true
```

### 5.5 拖动选区视窗（标注跟着走）

```
mouseDown :845 handle(at:of:) == .body → dragMode=.move(grab, original) + selectionDragBaseline=(原矩形, 原元素表)
mouseDragged :911 → setSelection(original.offsetBy(总位移))
setSelection → retargetElements :263
    ├─ baseRect/baseElements ← **基准**（不是上一帧）
    ├─ d = MSIntPoint.documentDelta(baseRect → new, scale)   MSCore/MSIntGeometry.swift:34
    ├─ 每个元素 translated(by:d)；跑到新画布外的 → .remove，其余 → .replace
    └─ compose 成一条撤销记录；dropped>0 → delegate.didDropAnnotations → toast
draw → drawSelectionContents :375 绘制目标吸网格 → 取样 → 合成缓存命中判断 :478
mouseUp → logDragGeometryCheck :440 打一条 V-070 读数（帧/小数边/取样≠画布/设备行变化/chrome 扫过）
```

### 5.6 拖动一条元素

```
mouseDown :819 tool==.select 且命中 → selectedID=hit.id ; dragMode=.moveElement(recorder:MSDragRecorder(element:), grab:画布点)
mouseDragged :920 → dp=canvasPoint → dx/dy=dp-grab
 :929 moved = recorder.elementBefore.translated(by: 总位移)   ← 加在**起点**那份元素上
 :934 dragMode 带着更新过的 recorder 重新赋值（松手时才知道起点）
mouseUp :956 recorder.command → history.apply(.replace)   ← 上百次拖动＝一条记录
```

### 5.7 Enter → 贴出并复制

```
handleKey :1161 Enter → commit(defaultIntent(from: preferences.commitBehavior)) :1207
 → delegate.overlay(_:didRequest:) :1215
coordinator :487 overlay(didRequest:.pin)
 ├─ run(.commitRequested(.pin)) → selecting→committing，effects [.closeOverlay,.openPin,.restoreFocus]
 │    perform(_:) :617 → closeOverlay :572（**不清 frozenFrame**）+ restoreFocus :639
 ├─ commit(:378)
 │    ├─ RegionCropper.crop(frame, globalSelection, display)   → MSCaptureFrame（像素精确，不重采样）
 │    ├─ doc = overlayView.annotationDocument :1257
 │    ├─ baker.bake(doc, cropped.image) → MSAnnotationRenderer.render(intent:.export)
 │    ├─ MSPinContent(document, source, scale, sourcePixelRect) → pins.open → NSPanel 出现
 │    ├─ clipboard.write(image, scale)（Q-05：贴出本身带复制）
 │    └─ onToast("已贴出并复制 W×H")
 └─ finishEffects :435 → closeOverlay + run(.effectsFinished) → committing→idle → run() 释放 frozenFrame
```

### 5.8 ⌘C / ⌘S / ⇧⌘S

`handleKey :1163/:1169` → `didRequest(.copy|.savePanel|.quickSave)` → reducer `:129-143` 给 `[.closeOverlay, .bakeAndCopy|saveToFile, .restoreFocus]` → `commit(:378)` 的第二支（`:390-410`，Task 里编码/写盘后 `finishEffects`）。落盘路径：`exportDirectory()`（`:444`，展开 `~`）→ `MSFileExporter.save` → `uniqueURL` 防撞。

### 5.9 贴图再编辑 → 复制

```
E / 右键 → MSPinView.keyDown :541 或 menuToggleEdit → onAction(.toggleEdit)
 → MSPinWindow.pinDidRequestToggleEdit :116（isEditing.toggle + 翻 isMovableByWindowBackground + markDirty）
 → applyStrip :284（stripHeight → resizeWindow → needsDisplay）
 画：mouseDown :401（工具带优先）→ draft → mouseDragged :450 → mouseUp :464 history.apply(.insert)
 复制：⌘C → onAction(.copy) :109 → delegate → coordinator.pinDidRequestCopy :586
        → pinView.bakedImage()（**与视图绘制无关的渲染器路径**）→ clipboard.write
```

### 5.10 设置改动 → 生效（两条路）

| 项 | 生效方式 | 代码 |
|---|---|---|
| 明暗、放大镜开关 | **立刻**：`coordinator.reapplyChromePreferences()` 改活窗 | `App/MSAppDelegate.swift:1155-1167` → `MSSession/…:503-512` |
| 样式默认值（描边/线宽/字号/模糊） | 下次建遮罩时 `applyDefaults` | `MSSession/…:329` |
| 提交动作、导出目录/格式/命名、热键 | 写盘即生效（读时取） | `settings.update { … }` + `register`/`rebind` |
| `appearance` 为什么不用重开遮罩 | 视图只读 `effectiveAppearance`，窗的 `appearance` 被换 → 自动跟 | `MSOverlay/MSOverlayView.swift:580-582` + `MSSession/…:516-522` |

### 5.11 放大镜取色

```
mouseMoved :777 → loupeAnchor=视图点 ; loupeForced=按 ⌥
draw :345 → drawLoupe :593 → MSLoupeModel.pixel/rect/gridRect/centerCell/readout
C（不带 ⌘）:1174 → loupeCopyString() → delegate.didPickColor
 → coordinator :524 run(.colorCopyRequested) → effect .copyColorText → clipboard.writeText → toast
⇧C :1176 → cycleLoupeFormat（hex ⇄ rgb，只有两档）
```

### 5.12 检查更新（唯一出网链）

```
菜单「检查更新…」:1011 → MSUpdater.check(:29) → JSONDecoder → MSUpdateManifest.decide（MSCore/MSUpdate.swift:66）
 → present(:105) NSAlert 三键
   ├─ 下载更新包 → download(:57)：HTTP 200 + 字节数 + SHA-256 三关，任一不过 **删临时文件** 返回 nil
   │              → 过了才 NSWorkspace.open(file)（挂载）
   ├─ 复制下载链接 → NSPasteboard 写串
   └─ 稍后 → 什么都不做（无自动重试、无后台轮询）
```

## 6. 会话状态机

`MSSessionReducer`（`MSSession/MSSessionCoordinator.swift:61`）的迁移表，按"谁执行这个效果"标注：

| 现相位 | 事件 | 新相位 | 效果（执行者） |
|---|---|---|---|
| idle | `hotKeyPressed(.snip)` | frozen | freeze、showOverlay（**启动流**） |
| idle | `hotKeyPressed(.fullScreen)` | committing | freeze、bakeAndCopy、closeOverlay、restoreFocus（**提交流**） |
| idle | `hotKeyPressed(.pinClipboard)` | idle | openPin（提交流） |
| idle | `permissionState(.denied)` | gate | showPermissionGate（`onNeedsPermission` → App） |
| frozen | `overlayShown` | selecting | — |
| gate | `permissionState(.granted)` | idle | toast("需要重启…") |
| selecting | `selectionChanged(w,h)` | selecting | log（`hasSelection = w>3 && h>3`） |
| selecting/editing | `annotationsDropped(n)` | 同 | log + warnClearAnnotations（文案 `MSSessionCopy`） |
| selecting/editing | `elementCountChanged(n)` | 同 | log（`hasElements = n>0`） |
| selecting | `drawBegan` | editing | 无选区 → toast("先框选区域") |
| editing | `drawEnded` | selecting | log |
| selecting/editing | `commitRequested(intent)` | committing | 按 intent 给 closeOverlay + 一个出口效果 + restoreFocus |
| selecting/editing | `colorCopyRequested(t)` | 同 | copyColorText |
| frozen/selecting/editing | `captureFailed(reason)` | failed | closeOverlay、restoreFocus、toast(reason) |
| committing/failed | `effectsFinished` | idle | — |
| 其它组合 | 任何事件 | **不动** | log rejected（`:162-170`） |

`perform(_:)`（`:617`）穷举每个 effect，没有 `default`——新增一个 effect 忘了交代就编译不过。这是 `B-018`（`default: break` 吞掉 `.closeOverlay`，整屏吃点击像死机）换来的结构。

## 7. 绘制结构（顺序本身是判据）

| 序 | 遮罩 `MSOverlayView.draw`（`:316`） | 贴图 `MSPinView.draw`（`:205`） |
|---|---|---|
| 1 | 冻结帧整屏 | 位图（zoom>1 关插值） |
| 2 | 四带暗化（有选区）或整屏暗化 + 提示 | 矢量元素层（CTM 缩放到视图） |
| 3 | 选区内容（合成图，绘制目标吸到设备网格） | 草稿层（若编辑中） |
| 4 | 草稿矢量层（blur 例外） | 编辑态边框 |
| 5 | 选中元素高亮盒 | 编辑态工具带（或字母提示） |
| 6 | 选区边框 + 8 把手 | 徽章（缩放/透明/未导出） |
| 7 | 工具条（**先算 layout**） | **边缘光晕（最后画 + 偶奇裁到留白）** |
| 8 | 尺寸药丸（避让工具条）→ chrome 扫过自检 | — |
| 9 | 放大镜（**永远压过贴图**） | — |
| 10 | 左上 ✕ 与提示条 | — |

两条"顺序不是审美问题"的实证：贴图光晕若画在内容之前，就会吃掉内容像素（`V-057`）；遮罩读数若用上一帧的 `toolbarLayout` 避让，同帧就会盖住（`:336-339`）。

## 8. 事件路由优先级

**遮罩 `mouseDown`（`:783-855`）**：① ✕ 命中区 → 取消；② 工具条（tool → color → action → blank）；③ 在文字编辑态且点框外 → 先提交这段字；④ `tool == .text` 且点在选区内 → 起 field editor；⑤ 点击型工具（badge/eraser）→ `performClickAction`；⑥ `tool == .select` 且点在选区内 → 命中元素则进入元素拖动，否则取消选中；⑦ 有 `annotationKind` 且点在选区内 → 起草稿；⑧ 以上都不是 → **拖选区**（body=移动 / 把手=改尺寸 / 空白=新框）。

**遮罩键盘（`:1153-1205`）**：文字子态优先（Esc 放弃 / Enter 提交 / ⇧Enter 交回 field editor）→ Esc / Enter / ⌘C / ⌘P / ⌘S / ⌘⇧S / C（取色）/ ⇧C（切格式）/ ⌘Z / ⌘⇧Z / ⌘] / ⌘[ / Delete → 字母选工具（再按同一个键＝收回工具）→ `[` `]` 调线宽 → 其余 `super.keyDown`。

**贴图键盘（`:521-546`）**：编辑态先认工具字母与 Enter/Esc；再认 ⌘C/⌘S/⌘W/E/⌘Z/⌘0。`E` 的上下文冲突按"**浏览态归贴图、编辑态归工具**"解（真源 `design/keymap.md` §4）。

## 9. 接缝结构（协议 → 生产实现 → 测试替身）

| 接缝 | 定义 | 生产实现 | 测试替身 |
|---|---|---|---|
| 采集 | `MSCapture/ScreenCapture.swift:28` `ScreenCapturing` | SCK / CoreGraphics 两个 struct | `MSFakeCapturer`（可注入失败） |
| 剪贴板 | `MSCore/MSExternalSeams.swift:26` `MSPasteboardWriting` | `App/MSAppDelegate.swift:16` `MSSystemPasteboard` | `MSFakePasteboard` |
| 文件系统 | 同上 `:33` `MSFileWriting` | `DiskFileWriter` | `MSFakeFileWriter` |
| 时钟 | 同上 `:6` `MSClock` | — | `FixedClock`（**当前无人消费**，§12） |
| 渲染 | `MSAnnotate/MSAnnotationRenderer.swift:11` `MSAnnotationRendering` | `MSAnnotationRenderer` | 基线快照测试直接用它 |
| 权限申请 | `MSSession/…:202` `permissionRequester` 闭包 | `PermissionProbe.requestScreenRecording` | 测试注入固定档位 |
| 偏好读 | `MSSettings/…:117` `MSReadingPreferences` | `MSSettingsStore` | 直接造 `MSAppPreferences` |
| 是否呈现遮罩 | `MSSession/…:196` `presentsOverlay` | 恒 true | false ⇒ 端到端判据不劫持屏幕 |
| 热键 | `MSHotKey/…:25` `MSHotKeyServing` | `CarbonHotKeyService` | `MSFakeHotKeyService.trigger` |

另一类"测试缝"是 `internal`（非 public）成员 + `@testable`：`MSOverlayView.document/selectedID/history/editorTextView`、`*ForProbe` 只读口、`CarbonHotKeyService.dispatch`。共同目的是**测试直接喂状态**，不靠合成鼠标事件构造前置。

## 10. 探针体系（同一份二进制的另一副面孔）

`App/main.swift` 是一串 CLI 分发。每个 `probe*` 方法的形状都一样：**起 app → 定时调一个方法 → 把读数写 `/tmp/macshot-probe-*.txt` + 打 oslog → `exit(rc)`**。

| make 目标 | 入口 | 读数 | 会打扰你什么 |
|---|---|---|---|
| `make probe` | `--probe-capture` | 尺寸/scale/degenerate/5 次耗时/中心像素 | 无 |
| `make probe-permission` | `--probe-permission` | `screenRecording=granted|denied` | 无 |
| `make probe-menu` | `--probe-menu` | 菜单行数 + 权限行是否真挂在菜单上 | 无 |
| `make probe-chrome` | `--dump-chrome` | `build/chrome.png`（可带 `loupe`/`draft`） | 无 |
| `make probe-clipboard` | `--probe-clipboard` | 读回 types/DPI/TIFF/哨兵 | **覆盖剪贴板** |
| `make probe-toast` | `--probe-toast` | 面板数/层级/是否自隐 | 屏上闪三条 toast |
| `make probe-settings` | `--probe-settings` | 控件清单 + y 范围 + 登录项档位；**裁了就 rc=7** | 开设置窗 |
| `make probe-pin` / `probe-pin-real` / `probe-loupe-real` / `probe-freeze` | 各自分支 | 真壳闭环读数 | **开遮罩数秒** |
| `make probe-memory` | `--probe-memory` | RSS 逐张增量、关后残留、两轮区分实验 | 开 N 个窗 |
| `make probe-hotkey` | `--probe-hotkey` | 改绑→退出→读盘→还原 | **临时改你的快捷键** |
| `make probe-update` | `--probe-update <url>` | `file://` 假源跑完整链，含"篡改校验和必须拒绝" | 无 |

读代码时把探针当**可读的判据说明书**用：想知道"这段逻辑被认为需要证什么"，看它对应哪个 `probe*` 最快。

## 11. 门禁与代码结构的对应

| 门禁 | 机检什么 | 对应结构 |
|---|---|---|
| `scripts/check-deps.sh:7-36` | import 必须在允许表内；`MSCore`/`MSAnnotate` 不许 AppKit | §1.3 的四条架构边 |
| `scripts/check-style.sh:27-35` | 禁 `try!`/`as!`/`fatalError`（`init?(coder` 除外）；网络只许 `App/MSUpdater.swift`；禁 `default: break`；禁自造单例 | §4.9 的穷举分发、§2.3 的状态归属 |
| `scripts/check-style.sh:50-56` | 文件 >400 行 ⇒ WARN（名单见 §12.1） | 表面层两个大文件 |
| `scripts/check-permissions.sh:14-40` | 源码里不许出现全局按键监听/事件 tap/辅助功能/连续采集；出网点必须只有一个 | `MSOverlayWindow.teardown` 的历史注释、`MSUpdater` |
| `scripts/check-docs.py:20-33` | `文档#ID` 引用必须可解析 | 本文刻意只用裸 ID |
| `scripts/check-docs.py:54-77` | 放大镜默认档**代码与规格必须同边**，旧措辞不许残留 | `MSSettings/MSAppPreferences.swift:86` |
| `make test` + `Tests/*` | 单测（swift-testing；32 个文件、184 个 `@Test` 声明） | §12 的反证要求 |

## 12. 结构债与断点（诚实清单，学习"哪里可以再改"）

这一节是**读代码读出来的现状**，不是待办台账（待办在 `docs/tasks/todo.md` 与 `blocked.md`）。每条都可反查。

### 12.1 超过 400 行的文件（`check-style` 长期 WARN）

| 文件 | 行数 | 结构上的分离点 |
|---|---:|---|
| `App/MSAppDelegate.swift` | 1287 | 装配（<150 行）与 **十几个探针**（约 700 行）混在一个类里；把探针拆成 `App/Probes/` 若干 extension 即可 |
| `MSOverlay/MSOverlayView.swift` | 1270 | 已是七段（`// MARK`），可拆：chrome 绘制、放大镜、文字子态、事件路由各成一支 |
| `MSSession/MSSessionCoordinator.swift` | 661 | reducer 可独立成文件；commit 的四出口可独立 |
| `MSPin/MSPinWindow.swift` | 612 | `MSPinView` 的编辑态工具带（`:267-364`）可独立 |

### 12.2 定义存在、路径不通（无调用者的代码）

| 位置 | 内容 | 后果 |
|---|---|---|
| `App/MSAppDelegate.swift:582` | `probeMemory(count:w:h:holdMs:)` 旧重载（约 80 行） | `App/main.swift:180` 走的是 `:474` 带 `rounds` 的那份 ⇒ 这份**永不执行**，两版读数口径已经开始分叉 |
| `MSPin/MSPinWindow.swift:476` | `MSPinView.eraseAt(viewPoint:)` | 橡皮擦在贴图里走 `performClickAction`（`:433`），这份是遗留分支 |
| `MSCore/MSDisplay.swift:31` | `fullLogicalSelection` | 等价于 `logicalFrame`，没人用 |
| `MSCore/MSExternalSeams.swift:6-19` | `MSClock` / `SystemClock` / `FixedClock` | 没有任何模块持有它；会话直接用 `ContinuousClock.now` 与 `Date()` |
| `MSCore/MSExternalSeams.swift:39` | `MSFileError.directoryUnusable` | 从未构造；目录不可用会落到 `writeFailed` |
| `MSCore/MSSelectionGeometry.swift:128` | `snapTargets` | **磁吸候选/就近吸附（`:138`）没接进拖动**：文档描述过"贴其他贴图边缘"，实现只有测试覆盖 `snapped` |
| `MSCore/MSSelectionGeometry.swift:91` | `moved(by:rect:clampTo:)` | 遮罩在 `:912` 直接 `original.offsetBy(...)`，**没有钳进屏内**：拖动可以把选区推出屏幕 |
| `MSCore/MSSelectionGeometry.swift:68` | `resized(lockedAspect:)` 的等比参数 | 调用方从不传；等比改尺寸未实现 |
| `MSAnnotate/MSAnnotationGeometry.swift:104` | `scaled(_:factor:about:)` | 注释说明留给 FR-ANN-012，当前形态是"改选区就清/保留"（`Q-11` 改判后为原地保留） |
| `MSExport/MSExport.swift:66`、`:94` | `tiff(...)`、`MSImageDecoder` | 只被测试用（产品只写 PNG，`Q-04`） |

### 12.3 死计算与空操作

| 位置 | 内容 |
|---|---|
| `MSOverlay/MSOverlayView.swift:914-918` | `.resize` 分支先算了一个 `t`，随后 `_ = t`，真正传给 `resized` 的是 `translation(for:…)`（`:1112`）——同一件事算了两遍，留下一具尸体 |
| `MSAnnotate/MSAnnotationRenderer.swift:28`、`:35` | `let h = CGFloat(size.height)` 之后 `_ = h`（翻转逻辑挪进 `renderElements` 后残留） |
| `MSSession/MSSessionCoordinator.swift:380` | `selection?.offsetBy(dx: 0, dy: 0)` 是空操作，读起来像"这里要换算却忘了" |
| `MSPin/MSPinWindow.swift:599-605` | `closeAll(askUser:)` 的参数被 `_ = askUser` 丢掉；调用点（`MSSession/…:609`）也从没传 |
| `scripts/check-deps.sh:39-41` | 一个 `if` 的 body 只有 `: # placeholder`，永不生效 |
| `scripts/check-style.sh:38-47` | `zh=$(python3 …)` 统计完没有消费者（`:48` 注释解释了 ADR-016 已裁不做本地化，但代码留着） |
| `scripts/check-style.sh:34-35` | 单例禁令的排除表里含 `App/`，等于**整个 App 层不受这条约束**（`ButtonBox.shared` 因此放过） |

### 12.4 兜底值 ≠ 出厂值（同一个陷阱的两个实例）

| 位置 | 视图兜底 | 出厂默认 |
|---|---|---|
| `MSOverlay/MSOverlayView.swift:174` | `blurRadius = 14` | `MSSettings/MSAppPreferences.swift:68` = 12 |
| `MSOverlay/MSOverlayView.swift:178` | `autoLoupeWhileDragging = true` | `MSSettings/MSAppPreferences.swift:86` = false（`Q-07` 改判档） |

生产路径靠会话在建窗后立刻覆盖（`MSSession/…:329-331`）才没暴露；但**任何直接 `new MSOverlayView` 的表面**（测试、`--dump-chrome`）若忘了覆盖，就会跑在改判前的档上。`:169-171` 的注释本身就在说这段历史（`A-11`：字段被写死在视图里，设置项没有消费者）。

### 12.5 委托双通知

`MSOverlayView.setSelection`（`:246-248` 与 `:258`）在同一帧可以报两次 `selectionDidChange`，会话因此向 reducer 喂两次 `.selectionChanged`。当前效果只有 log，所以不显；但它让"每次选区变化一条事件"这条假设不成立。同一行还有一处结构味道：`host` 为 nil 时**新建一个 `MSOverlayWindow` 只为了当参数**（`:258`）。

### 12.6 自检代码常驻生产

`MSOverlay/MSOverlayView.swift:401-446` 的 8 个 `v070*` 字段 + 3 个函数是 `V-070` 的读数装置，`draw` 里第 8 步每次都跑。留着的理由写在注释里（真机才有"小数边"这一半证据），代价是给视图加了一层与业务无关的状态；`compositeBakeCount`（`:491`）、`dragModeForProbe`（`:559`）等 `*ForProbe` 同属这类"为判据而存在的公共面"。

### 12.7 注释漂移（文档注释挂错了函数）

| 位置 | 现状 |
|---|---|
| `MSCore/MSIntGeometry.swift:20-27` | 描述 `documentDelta` 的三行说明挂在 `snappedToPixelGrid` 头上，而 `documentDelta` 自己另有一段 |
| `MSAnnotate/MSAnnotationDocument.swift:67-70` | `boundsOverride` 的说明（"自由曲线可缓存 bounds"）被并进了 `translated(by:)` 的注释块，三个说明叠在一起，字段声明跑到 `:83` |

对本项目尤其要注意：这里的注释承载的是**事故史与约束**（"不许再写回来"、"顺序有讲究"），挂错位置会让后来人把约束读到错误的函数上。

### 12.8 刻意的重复（不要顺手合并）

| 重复 | 位置 | 为什么留着 |
|---|---|---|
| `MSOverlayIcons` ≈ `MSPinIcons`（逐行相同） | `MSOverlay/MSOverlayIcons.swift`、`MSPin/MSPinIcons.swift` | `check-deps` 不许 `MSAnnotate` import AppKit，而 SF Symbol 只能经 `NSImage`；事实表（`MSAnnotationIconTable`）只有一份。收拢成共享 UI-kit 模块**要一条 ADR**（`B-031`） |
| 设置窗与权限窗的 `label()` / `button()` / `labeledRow()` | `App/MSAppDelegate.swift:1251-1272`、`App/MSHotKeyEditor.swift:165-178` | 同为 App 层，可以合并，目前没合 |

### 12.9 格式与缩进的历史伤

多轮插入留下了一些缩进不齐的块，读起来会误判作用域：`App/MSAppDelegate.swift:583-663`（旧 `probeMemory` 的闭包体整段多缩一层，`:647-652` 又突然退回 8 空格）、`:699-705`（`probePin` 里 `report` 的函数体从 20 空格跳到 12 空格再回 16）。

另一类同形状的问题：**贴着函数却不属于它**的 `///` 说明块——`App/MSAppDelegate.swift:206-215` 把 `--snip-then-cancel`/`--probe-pin`/`--probe-settings` 三条探针的说明堆在 `probeSettings` 一个函数头上，`:575-581` 同样把 `--probe-hotkey`/`--probe-memory` 的说明叠在 `probeMemory` 上，而 `:351-357` 与 `:575-581` 几乎是同一段文字的两份拷贝。这些不影响行为，但会误导读码——正是 §12.7 那条风险的低配版本。

### 12.10 台账读数与代码现状的偏差（**已报，未擅自改**）

`AGENTS.md` §0 写"10 模块 + 166 条单测"，而 `Packages/MacShotKit/Tests/` 现有 32 个测试文件、184 个 `@Test` 声明。这条按纪律**只报不改**（`AGENTS.md` 属先报后改的家，单测条数的真源在 `make test` 的实际输出）。读码时以此为准：**行数、符号、调用关系一律从代码反查，台账里的统计数可能已经旧了**。

## 13. 上手路线

### 13.1 三小时读码顺序

| 阶段 | 读什么 | 目标 |
|---|---|---|
| 30 分钟 | `AGENTS.md` → 本文 §1/§2/§3 → `docs/architecture/overview.md` | 知道有几层、数据往哪流、坐标系长什么样 |
| 40 分钟 | `MSCore/MSIntGeometry.swift` → `MSSelectionGeometry.swift` → `MSDisplay.swift`；同批跑 `Tests/MSCoreTests/MSGeometryTests.swift` | 把"值层"当纯数学读完；测试就是它的用法示例 |
| 50 分钟 | `MSSession/MSSessionCoordinator.swift` 全文（reducer 先读），对照本文 §5.2/§5.7 | 懂编排：事件 → 相位 → 效果 → 谁执行 |
| 40 分钟 | `MSOverlay/MSOverlayView.swift` 按 §7/§8 两张表**分段**读 + `Tests/MSOverlayTests/` | 交互面；先读绘制顺序，再读事件优先级 |
| 20 分钟 | `MSAnnotate/MSAnnotationRenderer.swift` + `MSPin/MSPinWindow.swift:205-260` | 一条渲染路径喂三个意图；贴图的矢量重画与光晕 |

配套动手：`make doctor`、`make build`、`make test`、`make probe-chrome`（不开遮罩就能看到界面几何）、`make check`。

### 13.2 五个练习（每条列出**必须同批改的家**）

| 练习 | 要碰的位置 | 会被哪条门禁/判据卡 |
|---|---|---|
| 加一个"直线"工具 | `MSAnnotate/MSTool.swift`（letter + annotationKind）、`MSAnnotationDocument.swift` 的 kind 表、渲染器 `draw`（`line` 已有分支）、`MSTool` 图标事实表、色/工具格数（工具条宽度自然变） | `ToolbarGeometryTests`（动作区 250pt 预算）、`check-deps`（别在 Core/Annotate 引 AppKit）、**贴图侧** `MSPin/MSPinWindow.swift:275` 的工具过滤 |
| 把选区磁吸接上 | `MSOverlayView.mouseDragged`（`:901-919`）调 `MSSelectionGeometry.snapTargets`/`snapped`，吸附只作用于**绘制与选区落定**，读数与命中仍用真实浮点选区 | `V-070` 的零容差判据（`SelectionDragPixelStabilityTests`）会立刻教你：吸附必须走设备网格 |
| 加一个偏好项 | `MSAppPreferences`（字段 + 默认 + 是否升 schemaVersion）、**读旧文件的迁移规则**（`:134-152` 两条范式）、设置窗（`App/MSAppDelegate.swift:1022+`）、消费者（若影响已开着的遮罩 → `reapplyChromePreferences`） | `SettingsTakeEffectTests`、`check-docs` 的默认档同边检查；纪律："改默认值必须同批改读旧文件的规则" |
| 给贴图加一个导出格式 | `MSCore/MSCommitIntent.swift` 的 `MSImageFormat`（追加 case）、`MSExport` 编码与 `save` 的 switch、设置窗格式段 | `perform`/`save` 的**穷举**要求（不许 `default:`）；命名模板的扩展名 |
| 修一个"看起来闪"的绘制问题 | 先读 §3.1 与 §7，再看 `V-070` 自检的读数行（一次拖动一条 log）；改完跑 `SelectionDragPixelStabilityTests` | 判据零容差：取样尺寸==画布尺寸、元素设备行恒定、像素包围盒恒定；夹具必须是**有周期的条纹** + **小数起点**，否则判据空转 |

### 13.3 三条最容易踩的结构陷阱

1. **"画在一处、点在另一处"**：任何新控件必须让绘制与命中读同一份几何（`MSAnnotationToolbar.boxes` / `actionBoxes` / `flow`、`OverlayChrome.*Rect`、`MSPinView.imageRect`）。这条在项目里已经付过三次学费。
2. **顺手换算坐标**：新增换算必须成对（正向 + 反向）并落进 `MSCore`，附单测（`ADR-013`）。视图里出现 `* scale`、`maxY -` 这类就地算术，就是要出事的形状。
3. **用 `default:` 兜住分发**：effect / command / intent 的 switch 必须穷举。漏一条的后果是功能静默不响（`B-018`），而不是编译报错。

## 附：名词速查

| 词 | 在这份代码里指什么 |
|---|---|
| 冻结帧 | 会话开始时抓的那一屏整屏位图（`MSCaptureFrame`），之后所有裁剪都从它来 |
| 遮罩 | 全屏 borderless 窗 + `MSOverlayView`，选区与标注的工作面 |
| 选区 | 视图空间（y-up 逻辑点）的 `CGRect`；导出口径问 `globalSelection`，像素口径问 `pixelRect` |
| 画布 / 文档 | 选区本地像素坐标（y-down）+ 元素数组 = `MSAnnotationDocument` |
| 草稿（draft） | 拖拽中尚未入文档的那个元素，走矢量层实时上屏 |
| 烘焙 | `文档 + 源位图 → CGImage`，单向，导出不携带文档 |
| 贴图（pin） | 置顶的小窗，持有**文档 + 位图**（不是烘焙图），可再编辑 |
| 出口 / intent | 提交动作的四类：复制 / 贴出 / 保存面板 / 快存 |
| 接缝（seam） | 包住外部世界的薄协议，使能力模块能无屏、无剪贴板、无磁盘地测 |
| 探针（probe） | 同一份二进制的 CLI 面，输出可读判据；`make probe-*` |
| 判据 | "做完了"的证据规格，见 `docs/protocol/verification.md`；本文只标编号 |
