# 采集管线（冻结帧 → 选区 → 裁剪）

> 派生自：`docs/charter.md`#术语表、ADR-007（后端）、ADR-008（冻结语义）、ADR-013（坐标规约）、ADR-003（最低系统）。
> 本文是**采集管线的机制真源**；"选哪条 API"不在这里论证，见 ADR-007。

## 1. 管线总图

```mermaid
flowchart LR
  A[热键事件] --> B[取光标所在显示器<br/>MSDisplays.display(under:)]
  B --> C[快照显示器布局<br/>LayoutSnapshot]
  C --> D[整屏抓取<br/>ScreenCapturing.freeze]
  D --> E[MSCaptureFrame<br/>image + scale + display + sourcePixelRect]
  E --> F[遮罩显示冻结帧]
  F --> G[选区 CGRect 逻辑坐标]
  G --> H[RegionCropper:<br/>display.pixelRect(forLogical:)]
  H --> I[CGImage.cropping 无重采样]
  I --> J[AnnotationDocument<br/>canvasSize = 选区像素尺寸]
```

会话内所有输出（复制/保存/贴出）都从 `E` 派生，**绝不回源屏幕**。

## 2. 后端选择（细节论证在 ADR-007）

| 路径 | API | 用途 | 备注 |
|---|---|---|---|
| A（主） | `SCScreenshotManager.captureImage(contentFilter:configuration:)` | 单屏整屏一帧 | macOS 14 起可用（**版本与行为以官方文档核实为准，`T-004` 实测**）；比 `SCStream` 起流更轻，适合"一帧就走"的冻结语义 |
| A' | `SCStream` + 首帧回调 | A 不可用/需要连续帧时 | 起流成本与延迟更高，P1 前不引入 |
| B（兜底） | `CGDisplayCreateImage(_:)` | 已弃用（macOS 15 标记，**待核实具体版本**） | 仅在 Q-01 选 macOS 13 或 A 路径出问题时启用 |
| C（P1） | `SCContentFilter(desktopIndependentWindow:)` | 窗口/元素干净截图（FR-CAP-011） | 能拿到不含桌面的单窗位图，是"自动识别窗口"的最优路径 |

`CaptureBackendSelector` 只做一次决定（进程启动时），结果写日志 `capture.backend=<a|b>`，便于回归对比。

## 3. 冻结语义（ADR-008）

1. 一次会话 = 一次抓取。抓取在遮罩可见之前完成，遮罩画的正是这张位图，因此"背景不动"是实现属性而非技巧。
2. 抓取范围 = **单个显示器整屏**（Q-09 推荐 A）。跨屏选区（P2）时改为逐屏抓取 + 逻辑拼接，届时另开 ADR。
3. 抓取参数：`scale = display.scale`，像素尺寸 = `round(logicalSize × scale)`；`showCursor` 默认关闭（Snipaste 是否含光标**待核实**，见 `docs/reference/snipaste-gap.md`），设置项 `export.includeCursor` 留 P1。
4. 布局快照 `LayoutSnapshot` 在抓取时冻结（`[MSDisplay]` 数组），会话期间的热插拔不影响裁剪计算（FR-SESS-004），但要检测并记 `capture.display-snapshot-stale`。

## 4. 坐标与像素对齐（ADR-013 的执行细则）

唯一合法换算入口：`MSDisplay.pixelRect(forLogical:)`。

```
输入：selection（AppKit 全局逻辑，y 向上）
1. clip  = selection ∩ display.logicalFrame
2. local = CGRect(x: clip.minX − display.minX,
                  y: display.maxY − clip.maxY,        // 翻转为 y 向下
                  w: clip.width, h: clip.height)
3. pixel = MSIntRect(flippedLogical: local, scale: scale)
         其中 minX = round(local.minX*s)，maxX = round(local.maxX*s)，
              width = maxX − minX（**两条边各自取整**，不是 round(width*s)）
4. 钳制：0 ≤ minX ≤ pw，width ≤ pw − minX（同理 y）
```

为什么第 3 步要分别取整两条边：在 1.799x/1.6x 这类非整数缩放下，`round(w*s)` 与 `round(maxX*s)−round(minX*s)` 会差 1px，表现为选区右/下边缘多切或少切一行像素（FR-CAP-004 的判据就冲它来）。

裁剪用 `CGImage.cropping(to:)`：**不重采样**，因此 100% 显示的截图像素与屏幕像素一一对应。任何缩放只发生在显示侧（贴图缩放、导出缩放），且必须显式声明插值策略（见 `pin-window.md` §5、`annotate-model.md` §6）。

## 5. 无重采样链路的红线

| 环节 | 允许缩放？ | 要求 |
|---|---|---|
| 整屏抓取 | 否 | 输出即显示器原生像素 |
| 选区裁剪 | 否 | `cropping(to:)`，尺寸来自 §4 第 3 步 |
| 遮罩预览绘制 | 是（仅显示） | 位图按 1:1 像素绘制；缩放只允许出现在放大镜（近邻） |
| 标注渲染（预览） | 否 | 画布尺寸 = 选区像素尺寸 |
| 导出（复制/保存） | 否 | 烘焙输出尺寸 == 画布尺寸 |
| 贴图显示 | 是（近邻） | `interpolationQuality = .none`，标注矢量按同倍率重绘 → 边缘仍锐利 |

## 6. 权限与失败检测

- 屏幕录制（ScreenCapture/Screen Recording）为**必需**权限，属于 TCC 而不是 entitlement；无法通过 Info.plist 声明绕过。
- 探测：优先用系统提供的 preflight/request API（具体可用版本**待实测**，`T-004`）；不可用时退化为"抓一帧 → 判断是否退化"。
- 退化判据（启发式，需实测校准）：整屏所有像素等于壁纸均值或全黑，且同一台机器上另一个已知区域也如此 → 判为 `perm-missing`，走 FR-CAP-006 引导窗。**不允许**把黑图当成功交出去（`overview.md` §6 第 2 行）。
- 授权变更需重启进程：引导窗提供"打开系统设置"和"重启 MacShot"两个动作（FR-CAP-006 判据）。

## 7. 性能测量点（必须内建，不是临时插桩）

| 标记 | 起点 → 终点 | 对应 NFR |
|---|---|---|
| `t.hotkey→frozen` | 热键回调 → `MSCaptureFrame` 就绪 | 冻结采集耗时目标 |
| `t.frozen→overlay-visible` | 帧就绪 → 遮罩首帧绘制 | 唤起延迟目标 |
| `t.commit→clipboard-ready` | 提交事件 → `write` 返回 | 剪贴板写入目标 |
| `t.crop→doc-ready` | 选区确认 → 文档构建完成 | 标注准备 |

统一走 `MSLog.logger(.capture)`，字段只有几何与耗时，**不含像素内容**（隐私类 NFR）。实测数据落在 `docs/tasks/done.md` 对应条目证据栏，不写进本文。

## 8. 失败模式

| 现象 | 根因 | 处理 |
|---|---|---|
| 返回 nil | SCK 权限/内容过滤器无效 | 取消会话 + 引导窗；不重试 |
| 尺寸比期望小/大 1px | 缩放因子用了 `Int()` 截断 | 一律 `rounded()`；加 §4 单测 |
| 截到别的屏 | 用了 `main` 而非光标所在屏 | `display(under:)` 用会话开始时快照 |
| 有窗口阴影被切 | 冻结帧无阴影外的留白 | 属正常（整屏语义），不做特殊处理；窗口识别路径（P1）另议 |
| 遮罩出现后背景变了 | 抓帧与显示之间屏幕重绘 | 语义上不可能（遮罩画的就是那张帧），若出现即为 bug |
| 外接屏拔掉后崩 | 裁剪用了新布局 | §3.4 快照；加回归用例 |

## 9. 测试清单（对应 `docs/protocol/verification.md`）

- 单测（无头）：§4 换算在 scale ∈ {1, 2, 1.799, 1.6} × 选区 ∈ {整数点、半整数点、贴边、越界} 下的期望像素尺寸表；`RegionCropper` 不重采样（比对源/结果字节）。
- 假采集器：喂已知像素的测试卡 → 验导出图边缘列颜色（FR-CAP-004 的 V-002 脚本等价物）。
- 实拍（必须人跑）：双屏不同 scale、全屏 Safari 之上、拔屏、授权撤销后首启。
