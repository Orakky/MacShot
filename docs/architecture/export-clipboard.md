# 导出与剪贴板

> 机制真源：从 `AnnotationDocument` 到"用户能粘贴/打开的东西"。剪贴板表示 **ADR-014 已于 11-17 签＝仅 PNG**；命名模板字段是本文真源。

## 1. 唯一出口路径

```
AnnotationDocument + source CGImage
        │  AnnotationRendering.render(intent: .export)     ← 单向烘焙（charter §1.1 对策 3）
        ▼
     CGImage (canvasSize 尺寸，像素)
   ┌────┴─────────┬──────────────────┐
   ▼              ▼                  ▼
ClipboardWriter  FileExporter      PinWindow（不烘焙，走文档）
```

规则：**任何导出物都不携带文档**；`.macshot` 文档格式属 P1（`FR-EXP-012`），P0 不实现写入器。

## 2. 剪贴板

| 项 | 决策（待 ADR-014 accepted） | 依据 |
|---|---|---|
| 表示集合 | **我们只写一个 `public.png`**（11-17 Q-04 裁决）。但 `NSPasteboard.types` 里仍会出现 `public.tiff` / `NeXT TIFF v4.0` / `Apple PNG pasteboard type`——**那是 AppKit 自己派生的**，对照组（`NSPasteboardItem` 只塞 PNG）实测一模一样，拦不住也不必拦（`E-062`） | 双写 TIFF 是当初的猜测档，Snipaste 是否双写始终没找到官方出处。用户裁定只写 PNG，粘贴兼容性由用户自行实测（`V-003` 矩阵降级为自测记录，不再是 ADR 的决策门）。**代价要写明白**：走 `NSImage` 的原生目标（Pages/Word/Finder 拖动）历史上偏好 TIFF，若实测失败，恢复 TIFF 只是加回一个表示，不动数据结构 |
| 位图表示 | **不写** `NSBitmapImageRep` 类型化数据之外的东西 | 避免多份表示不一致 |
| 文件表示 | P0 不写 `fileURL`（写了会让"粘贴到聊天框"变成贴附件，行为不可控） | P1 与"拖出"一起定（`FR-EXP-011`） |
| 清空策略 | `clearContents()` 一次 → 同一次 `writeObjects` 写完 | 分两次写会出现"粘贴到半成品" |
| 线程 | 编码在后台（PNG 数据先在后台生成），`NSPasteboard.write` 在主线程一次完成 | FR/NFR 的"提交→剪贴板可读"目标 |
| `changeCount` | 写完记录并断言变化了 | 供测试与 `V-003` |
| 图像质量 | PNG 无损（`compressionFactor` 默认）；Snipaste 官方 FAQ 也说明剪贴板质量不可调，我们同样不提供 | `docs/reference/snipaste-gap.md` §5 |
| 剪贴板内容被别的应用抢先 | 写完回读 `changeCount`，不符则重试 1 次后报错（不静默） | `overview.md` §6 |

## 3. 色彩与 DPI（真实踩坑点）

Snipaste 的 Mac 版 changelog 多次专门修"剪贴板/文件的 DPI 与色彩配置"（`docs/reference/snipaste-gap.md` §5）→ 说明这两条是 macOS 截图工具的常规事故区，必须当成需求而不是巧合。

| 问题 | 规则 | 验证 |
|---|---|---|
| 尺寸被当成"2 倍大" | 导出图 DPI = `72 × scale`（4K 屏 scale=2 → 144 DPI），PNG 写 `pHYs`（`ppu = dpi/0.0254`，整数），TIFF 写 `ResolutionUnit=inch` + `XResolution/YResolution` | FR-EXP-004：读回 `kCGImagePropertyDPIWidth`；Pages 里放置量逻辑宽 |
| 颜色偏移（P3 vs sRGB） | **保留源位图的色彩描述文件**（SCK 帧常带宽色域）；不做色彩空间强转。若目标应用粘贴后偏色，先测"去掉 ICC"与"转 sRGB"两版再决定（不做无证据的统一转换） | `V-004` 实拍：截一张饱和红图，粘到 预览 / Pages / 浏览器 比对目视色 |
| 透明 | 截图无 alpha 需求；贴图复制时若源含透明（P1 拖入/剪贴板），PNG 保留 alpha，TIFF 保留 | `V-005` |
| 像素格式 | 一律 RGBA8；16-bit 源（外接专业屏）先转 8-bit 并记日志 | 待实测 |

## 4. 文件保存

```swift
public struct NamingTemplate {
    // 变量（真源就是这张表，别处只引用）
    // {yyyy} {MM} {dd} {HH} {mm} {ss}  时间
    // {width} {height}                 像素尺寸
    // {display}                        显示器本地化名（去空格）
    // {scale}                          @1x/@2x
    // {index}                          当日递增，从 1 开始，零填充 3 位
    // {tool}                           固定 "MacShot"
}
```

默认模板：`MacShot {yyyy}-{MM}-{dd} {HH}.{mm}.{ss}`（与 macOS 自带截图命名习惯一致，用户迁移成本低）。

| 项 | P0 行为 |
|---|---|
| `⌘S` | 保存面板，预填模板结果与默认目录 |
| `⌘⇧S` | 免面板直存默认目录（FR-EXP-003） |
| 默认目录 | **`~/Downloads/`**（11-19 用户改判，原 `~/Pictures/MacShot/`），首次自动创建；设置可改。`⌘S` 的保存面板 `directoryURL` 与 `⇧⌘S` 都走同一个 `exportDirectory()`，所以改默认两处一起动。旧文件迁移＝**认值不认版本**：只有等于 `MSAppPreferences.legacyExportDirectories` 里那几条历史默认的才回落（非沙盒，任意目录可写；不用安全书签，P1 若引入沙盒再补） |
| 重名 | 追加 `{index}`；判定用"存在即 +1"循环，连续 10 次不覆盖（判据来自 FR-EXP-003） |
| 格式 | PNG；JPEG 质量档 P1；WebP P2（Snipaste 免费即有 WebP，差距有意保留） |
| 目录不可用（卷卸载） | 回落到保存面板（`overview.md` §6） |
| 保存后 | 状态栏一次性提示"已保存 + 打开所在目录"（P1 `FR-EXP-013`）；P0 只写日志，不弹横幅（避免自用时被打扰） |

## 5. 提交意图（`CommitIntent`）

```swift
public enum CommitIntent: Sendable {
    case pin                         // 默认出口（11-17 裁决）：贴出 **并同时写入剪贴板**，之后可直接去粘贴 —— 也是 ⌘P
    case copy                        // ⌘C / ⌥Enter
    // copyAndPin 已删除：11-17 起「贴出」本身就带复制，它不再是另一个动作
    case savePanel                   // ⌘S
    case quickSave                   // ⌘⇧S
    case cancel                      // Esc：什么都不做（FR-SESS-002 判据：剪贴板哨兵不动）
}
```

默认出口由 `AppPreferences.commitBehavior` 决定（`pin` / `copy` / `save`），**枚举本身不含默认值**：
"按 Enter 发生什么"是会话层查表的结果，而不是 `CommitIntent` 的语义，这样改默认档不动任何状态机代码。

`cancel` 不写剪贴板 —— 这条要专门测（`CancelSentinelTests`），因为"顺手复制"是实现里最容易犯的错。
`pin` **反过来必须写**：11-17 的裁决就是"置顶时同时复制"，所以它的判据是"剪贴板里有 PNG 且能粘"，两条测试方向相反，不能互相顶替。

## 6. 与贴图的关系（D-04 的体现）

- 贴图显示 = 文档 live 渲染；**复制/保存贴图时 = 走 §1 的烘焙路径**，与遮罩内提交完全同一个函数，因此"贴图上看到的"与"复制出去的"必然一致（FR-EXP-002 判据）。
- 缩放/旋转（P1）只影响显示变换，导出恒按 100%（`pin-window.md` §3）。

## 7. 失败模式

| 现象 | 处理 |
|---|---|
| 权限缺失 | 不适用（剪贴板写入不需 TCC） |
| 大图画 PNG 耗时 | 编码在后台；提交动画期间完成，不阻塞（NFR 延迟目标） |
| 目录被删 | 重建 → 失败则回落保存面板 |
| 目标应用只认 TIFF | 不需要我们加：系统会从 PNG 派生 TIFF（`E-062` 对照组）。若某应用仍粘不上，记录进 `docs/runbook/troubleshooting.md`，先量它的实际请求类型再决定加不加表示 |
| 用户以为"复制的是屏幕原图没含标注" | 属渲染 bug，不是导出 bug；用 `annotate-model.md` §10.2 基线用例拦 |

## 8. 测试清单

1. 表示集合断言：包内用假 `MSPasteboardWriting` 断言**只收到一个 PNG 载荷**；真壳用 `make probe-clipboard` 打印 `NSPasteboard.types` + 对照组，分清"我们写的"与"系统派生的"。
2. `changeCount` 语义 + 哨兵不被 `cancel` 覆盖（FR-SESS-002）。
3. DPI 往返：PNG 写→读 `kCGImagePropertyTIFFXResolution` = `72×scale`，scale ∈ {1,2}（剪贴板路径实测 144，`E-062`）。
4. 命名模板展开：含非法字符、目录不存在、重名 10 次。
5. `CommitIntent` × 是否写剪贴板 的矩阵表（每条一行，全绿才算 `FR-EXP-001` 达成）。
6. 实拍偏色对照（`V-004`）。
