# 标注模型与渲染（D-04 的落点）

> 真源：**标注文档的数据结构、坐标空间、渲染器契约**。工具集合数量待 Q-03，schema 编码待 ADR-009（两者未 accepted 前不得写实现）。

## 1. 为什么这一层是正式产物

D-04 决定贴图携带**可编辑标注文档**。因此：
- 标注层不是"截图后的一次性效果"，而是与位图并列的第二份真相。
- `AnnotationDocument` 的结构从 M-1 出口起冻结（带 `schemaVersion`），任何新增字段只增不改语义。
- 导出（剪贴板/文件）走"文档 → 位图"的**单向烘焙**；导出物不携带文档（`docs/charter.md` §1.1 对策 3），避免双向同步。

## 2. 文档结构

```swift
public struct AnnotationDocument: Codable, Sendable, Equatable {
    public var schemaVersion: Int          // 当前 1
    public let canvasSize: MSIntSize       // 像素；= 选区像素尺寸（capture-pipeline.md §4）
    public var sourceRef: SourceRef?       // 位图来源描述（P0 只在内存有意义）
    public var elements: [Element]
    public var currentStyle: Style         // 下一个元素用的样式；不属于 elements
}

public struct Element: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: Kind
    public var points: [MSIntPoint]        // 画布像素坐标，y 向下
    public var style: Style
    public var zIndex: Int
    public var text: String                // text / badge 类使用，其他为空
}
```

JSON 形态（`.macshot` 未来即此 JSON + 位图，见 ADR-009）：

```json
{ "schemaVersion": 1,
  "canvas": { "w": 1600, "h": 900 },
  "elements": [
    { "id": "0C0A…", "kind": "arrow", "points": [{"x":120,"y":240},{"x":610,"y":180}],
      "style": { "stroke": [232,51,71,1], "lineWidth": 4, "arrowHead": "single", "dash": "solid" },
      "z": 0, "text": "" },
    { "id": "7F3B…", "kind": "blur", "points": [{"x":700,"y":300},{"x":1100,"y":420}],
      "style": { "blurKind": "pixelate", "blurRadius": 10 }, "z": 1 }
  ] }
```

编码约定：字段名稳定、`elements` 按 `zIndex, id` 稳定排序、颜色用 8bit RGBA 数组（不用色名，保证跨版本可读）、浮点一律 `Double` 且几何坐标一律整数。

## 3. 坐标空间（三条铁律）

1. **文档内只有画布像素空间**（origin 左上，y 向下，整数）。元素尺寸、字号、线宽都以像素为单位存储。
2. 视图空间（AppKit，y 向上）的翻转只发生在宿主 view 的 `isFlipped` 与 `NSAffineTransform` 上；文档不知道视图存在。
3. 因此**同一份文档在任何 backing scale 上渲染结果一致**，且贴图 200% 显示时不需要重新换算字号（FR-PIN-003 的实现前提）。

字号换算规则：`style.fontSize` 存像素值；从 UI 上的"pt 档位"（12/14/18/24/32）换算成像素时用 `round(pt × scale)`，换算发生在创建元素那一刻（之后不再依赖 scale）。

## 3b. schema v1 冻结清单（ADR-009，11-17 签）

> 形态**取自实跑输出**（`JSONEncoder` + `.sortedKeys`，见 E-057），不是照着手写文档。
> 冻结的含义：以下键名、rawValue 拼写、数值语义从此**只能加不能改**；改名/换语义＝v2，必须走迁移。

顶层：

| 键 | 类型 | 语义 | 冻结点 |
|---|---|---|---|
| `schemaVersion` | Int | 当前 = `1` | 读到时 **> 本地版本 ⇒ 拒绝并提示**，不许猜解（`NFR-018`） |
| `canvasSize` | `{width, height}` Int | **画布像素**，不是逻辑点 | 单位写死在字段名里，禁止改成点 |
| `badgeCounter` | Int | 序号自增值，从 1 起 | 撤销 `.badgeCounter(before:after:)` 依赖它 |
| `currentStyle` | Style | 新建元素用的样式 | 与元素内 style 同结构 |
| `elements` | [Element] | 元素表，顺序不承载语义（层级看 `z`） | 不许改成字典 |

Element：`id`(UUID，大写带连字符的 `String(uuid)`) / `kind`(见下) / `points`([{x,y}] 画布像素) / `style`(**每个元素自带一份完整 style**) / `z`(Int) / `text`(String，可空) / `variant`(String?，**可选字段**，缺键视为 nil) / `boundsOverride`(MSIntRect?，可选)。

Style：`stroke`{red,green,blue:UInt8 0…255; alpha:Double 0…1} / `fill`(同结构，可 null) / `lineWidth` / `cornerRadius` / `dash` / `arrowHead` / `fontSize` / `bold` / `blurKind` / `blurRadius`。

rawValue 冻结（拼写即契约）：

- `kind`：`rect` `ellipse` `arrow` `polyline` `freehand` `text` `badge` `blur` `eraser` `line` `spotlight` `crop`（后三个 P1，**先占位**，避免以后加值时被当成未知 kind）
- `dash`：`solid` `dash` `dot` · `arrowHead`：`single` `double` `triangle` · `blurKind`：`pixelate` `gaussian`
- `variant`：目前只有 `"pen"`；`null` = 荧光笔。加新值只能追加。

三条**已知不优雅但已冻结**的取舍，写清楚免得以后被当成 bug 顺手"优化"：

1. **每个元素复制一份完整 style**（13 个字段）。代价是文件冗余、改默认样式不会回写既有元素；收益是解码零依赖、元素自洽。要改成共享样式表属于 v2。
2. **`points` 是画布像素**而不是逻辑点，所以同一文档在不同 scale 显示器上尺寸含义不变（`ADR-013` 的代价与收益都在这里）。
3. **未知 `kind` ⇒ 拒绝整份文档**，不是跳过该元素。理由：静默丢元素比打不开更危险（`MSAnnotateTests` 有对应用例）。

迁移策略（同时冻结）：v1 无外部引用、无历史文件（Q-06 不落盘），所以**首版不需要迁移器**；出现 v2 时必须提供 `v1 → v2` 的显式转换函数并保留 v1 读取能力至少一个大版本。

## 4. 工具集合（Q-03，推荐 9 件，含橡皮擦）与 `points` 语义

| kind | 中文 | points 语义 | 可多段 | 参与烘焙 | 备注 |
|---|---|---|---|---|---|
| `rect` | 矩形 | [起点, 对角点] | 否 | 是 | 支持填充/圆角/虚线 |
| `ellipse` | 椭圆 | [外框起点, 外框对角点] | 否 | 是 | |
| `arrow` | 箭头 | [尾, 头] | 否 | 是 | 端点形状 3 种 |
| `polyline` | 折线箭头/折线 | 任意长度，末段带箭头 | 是 | 是 | 双击或 `Enter` 结束 |
| `freehand` | 画笔 / 荧光笔 | 轨迹采样点 | 是 | 是 | 荧光笔 = 半透明宽笔 + 混合模式 multiply |
| `text` | 文字 | [左上锚点] | 否 | 是 | **保留 `text`，不烘焙成形状**（FR-ANN-007） |
| `badge` | 序号/文字徽章 | [圆心] | 否 | 是 | 自增序号，半径随文本变（§5.3） |
| `blur` | 马赛克 / 模糊 | [起点, 对角点] | 否 | 是 | 需要源位图（§5.4） |
| `eraser` | 橡皮擦 | **不产生元素** | — | — | 删除命中的**最上层**元素（z 最大）；一次点击＝一条撤销记录；没命中任何元素时**不入栈**（否则用户要按一次 `⌘Z` 才撤销"没发生的事"） |

接线状态（2026-11-16）：`rect ellipse arrow polyline freehand(画笔/荧光笔两变体) blur badge eraser` 已在遮罩内可用（`MSTool`，键位按 `design/keymap.md` §3 真源；`rect` 此前占的是 `R`，与 §2 的"重复上次区域"撞车，已改回 `M`）。`text`(T) 已于同日接入（field editor 子态，判据见 §6b）。
`badge`/`eraser` 的行为判据在 `Tests/MSOverlayTests/AnnotationToolTests.swift`（含"撤销把序号计数器一起退回"与"未填充形状只有轮廓可命中"两条实测出来的语义）。
| `line` `spotlight` `crop` | 直线 / 聚光灯 / 二次裁剪 | 同上 | — | — | P1，Q-03 选项 B 才进 P0 |

`Kind` 用枚举而非字符串：JSON 编码为稳定 rawValue。新增 kind 属于 schema 演进（加 rawValue，不改旧值）。

> 公共件的归属（11-17）：工具表 `MSTool`、工具条度量 `MSAnnotationToolbar`、色板 `MSAnnotationPalette`
> 都在本模块——遮罩与贴图再编辑态共用同一条工具条，而依赖方向不许 `MSPin → MSOverlay`（`charter.md` §4）。
> **度量与格子只有一个家，摆放各表面自己定并各自测**（遮罩贴选区、贴图钉下沿）。

## 6b. 文字输入子态（ST-003 的实现契约）

| 项 | 定稿 | 判据 |
|---|---|---|
| 进入 | 工具 `T` + 在选区内按下 → 以落点为**文字左上角**开 field editor | `editorFrame` 单测：锚点画布 (0,0) 贴选区上沿、行数越多框越向下长 |
| 提交 | `Enter` 或 `⌘Enter` | `TextEditingTests`：提交后 `element.text` 逐字可读、`kind == .text`（不是位图，`FR-ANN-007`） |
| 换行 | `⇧Enter` **不**提交，交回 field editor 自己插换行 | 同一测试断言 `handleKey` 不消费该键且仍在子态 |
| 放弃 | `Esc` 只退子态，**不退会话**，且不入撤销栈 | 测试用 `Spy` 数 `overlayDidCancel` 次数：子态内 0 次，对照非子态 1 次 |
| 空文本 | 提交空串不入记录 | `undo` 返回 false |
| 再编辑 | 走 `.replace(before:after:)`，元素 id 不变 | 三行文本后 `elements.count` 仍 1 且 `id` 相同；bounds 高度增大 |
| 坐标 | 画布像素 ⇄ 视图点用 `MSIntPoint.canvasPoint/viewPoint` 成对函数（MSCore） | 往返单测 ×4 种 scale，漂移 ≤ 半像素 |

`⌘C/⌘V/⌘Z/删除/方向键` 在子态内一律返回"未消费"，交回 field editor —— 会话级快捷键不许在打字时抢键。

## 5. 渲染器契约

> 判据纪律（11-16 起）：渲染器的任何改动必须留下**像素级证据**——基线比对、墨迹包围盒或离屏渲染占比。
> 只断言文档内容（`element.text` 可读、`points` 正确）不算，因为它看不见「画面上到底有没有东西」（`V-044`、`E-052`）。
y-down 文档空间里的局部反翻只允许出现在文字与位图两处，且必须带注释说明符号。

```swift
public protocol AnnotationRendering: Sendable {
    func render(_ doc: AnnotationDocument,
                source: CGImage?,                 // blur/spotlight 必需；其他可空
                canvasSize: MSIntSize,
                scale: CGFloat,
                intent: RenderIntent) -> CGImage
}
public enum RenderIntent: Sendable {
    case preview   // 遮罩内实时：允许脏区增量、忽略导出专属设置
    case export    // 烘焙进位图：全量、确定性、无动画、DPI 由 MSExport 侧贴
    case pin       // 贴图显示：可含 1:1 之外的放大，blur 半径随显示倍率不变（像素域）
}
```

要求：
1. **同一输入三种 intent 的像素结果，除预览优化外必须一致** → 用基线 PNG 快照测试锁死（FR-ANN-002 判据）。
2. 渲染是纯函数：不读全局状态、不读 `UserDefaults`、不依赖当前显示器。
3. 输出尺寸恒等于 `canvasSize`，与 `scale` 无关（`scale` 只影响内部抗锯齿质量档位）。

### 5.1 绘制顺序
`elements` 按 `zIndex` 升序；每个元素内部：填充 → 描边 → 文字。`blur` 元素在烘焙阶段就地取源位图区域 → 处理 → 贴回，因此**模糊不受后续元素影响也不影响后续元素顺序以外的东西**（FR-ANN-006）。

### 5.2 荧光笔混合
用 `CGBlendMode.multiply` + `alpha < 1`，**不**用 `overlay`；导出与屏显必须同模式（否则"屏上粉、导出黑"）。列为 V-0xx 实拍项。

### 5.3 徽章
`badge` 的文本默认自增（1,2,3…），起始值在样式条可改；圆半径 = `round(fontSize × 0.72) + 宽度补偿`，补偿按文本位数走。半径公式属几何真源，改动要连基线图一起改。

### 5.4 模糊/马赛克
- `pixelate`：按 `blurRadius` 做块平均（无重采样渗色：块边界整数对齐）。
- `gaussian`：`CIFilter` 或手写可分离核 —— **决策待定**：`CIFilter` 引入 CoreImage 依赖，跨 macOS 版本核半径语义有差异；手写核可控但慢。ADR-021 占位（在 ADR-009 accepted 后开）。
- 二者都必须"重算"而非缓存烘焙结果，因为贴图缩放时源区域不变但显示倍率变（FR-ANN-006 第 2 句判据）。

### 5.5 文字测量
`MSAnnotate` 不 import AppKit 视图，因此测量走注入协议：

```swift
public protocol TextMeasuring: Sendable {
    func size(of text: String, style: Style, containerWidth: Int?) -> MSIntSize
    func layout(_ text: String, at origin: MSIntPoint, style: Style) -> TextRuns   // 供渲染器绘制
}
```
AppKit 实现（`NSAttributedString`）放 `App/` 或 `MSSession` 的适配层（ADR-002 相关，待定归属，记为 `T-0xx`）。自动换行宽度约束是 P1（FR-ANN-016）。

## 6. 几何、命中与选择

- `bounds(of:)`：由 `points` 推导；`text`/`badge` 走测量；自由手绘可带 `boundsOverride`。
- `hitTest(point:element:tolerance:)`：描边类给 `tolerance + lineWidth/2` 的带状命中；填充类只在有填充色时命中内部（与 `docs/design/screens.md#UI-002` 的命中表一致）。
- 8 个把手只在"选中且当前工具为选择工具"时出现；把手尺寸 7pt（视觉值来自设计 token，改一处即可）。
- 多选 P1（`FR-ANN-015` 之后再说），P0 只支持单选 + 拖拽。

## 7. 撤销栈（ADR-011）

命令式：`Insert / Remove / Mutate(before, after) / Reorder / StyleChange`，加 `Composite`。
- **一次拖拽 = 一条记录**（按下到抬起之间的 60 次 `Mutate` 合并成 1 条）。
- 文字编辑：进入编辑到 `⌘Enter` 提交为 1 条；`Esc` 不产生记录也不留下半成品。
- 栈深上限 200，超出丢最早；内存预算目标（**待实测**）：单文档历史 < 4MB。
- 跨提交不串联（FR-ANN-005 判据）：`commit` 后开新栈；贴图内再编辑的撤销栈**属于那张贴图**，退出编辑态不清空（这条是 D-04 的应有语义，写清楚防实现走偏）。

## 8. 改选区时已有标注怎么办（Q-11 → 11-18 用户改判）

现档：**屏幕位置还落在新选区里的标注原地保留，跑到外面的才清掉**，整件事是一条可撤销记录。
- 触发点：遮罩内拖动把手、方向键微调、切换全屏/重复上次区域（一切 `setSelection` 且 `previous != rect`）。
- 换算只有一个入口：`MSCore.MSIntPoint.documentDelta(selectionOld:to:scale:)`（`canvasPoint` 的差分形式，
  `ADR-013`）。元素锚点加这个量 ⇒ 屏幕位置不动；逆函数 `selectionDelta` 存在只为让单测能量出"两个方向互为逆运算"。
- **这条量必须落在设备网格上**：`documentDelta` 先把两个选区各自吸到 `snappedToPixelGrid` 再取边差，画布尺寸直接取 `pixelRect` 的尺寸（不再 `round(尺寸 × scale)` 各算一遍）。三条量同源之后「标注设备行 = 取样设备顶 + 画布 y」才是恒等式；分头取整时它每帧能差 1px，观感是「框不动、里面闪」（`V-070`、`E-110`）。
- 去留判据：元素外接框（`MSAnnotationGeometry.bounds`）与新画布矩形**相交即保留**，不相交才清。
  压线的元素保留下来、导出时被画布裁掉——这是有意的，不做"按比例缩放"（那是 `FR-ANN-012` 原案的 P1 形态，用户没要）。
- 撤销：`remove` + `replace` 合成一条 `composite`，`⌘Z` 一次连位置带条数一起还回。
- 提示：不再由"尺寸变了"驱动，改由 `annotationsDropped(n)` 驱动，`n>0` 才出现；文案单源
  `MSSessionCopy.annotationsDropped(_:)`（带条数 + "原地保留" + "⌘Z 可撤销"）。
- 历史沿革：临时默认 A（"全清 + 无法撤销"）11-17 落地、判据 `V-048`、事故记录 `E-056`；11-18 用户改判，
  `V-048` 标 superseded，新判据 `V-056`。

## 9. 与遮罩/贴图的宿主关系

| 宿主 | 持有 | 渲染 intent | 编辑能力 |
|---|---|---|---|
| 遮罩（会话） | 文档 + 选区裁剪出的源位图 | `preview` | 完整（M-4） |
| 贴图 | **同一份文档 + 源位图**（`PinContent.document`） | `pin` | 再编辑态（FR-PIN-005） |
| 导出 | 文档快照 | `export` | 无 |

一份渲染器、三个宿主。禁止为贴图另写一套绘制（`docs/architecture/pin-window.md` §4）。

## 10. 测试清单

1. schema 往返：`encode → decode → encode` 字节稳定；未知 `kind` / 高 `schemaVersion` 的拒绝路径。
2. 基线渲染：8 件工具 × 3 种 intent，固定输入 → 与 `Tests/Fixtures/*.png` 逐像素比对（容差 0）。
3. 命中表：边缘内/外、填充有无、把手、tolerance 随 scale。
4. 撤销合并：拖拽 100 次 `Mutate` → 栈内 1 条；`⌘Z` 次数与预期一致。
5. 模糊重算：同一文档在 scale 1 与 2 下渲染，块边界仍整数对齐。
6. 徽章自增：1→9→10→99 的半径与文本宽度表。
