# Swift 编码规范

> 真源：代码层面的约定。**不装 lint 工具**（ADR-015），所以每条"可机检"的规则都对应 `scripts/check-style.sh` 里一条 grep；不可机检的进评审清单。

## 1. 语言与版本
- Swift 6.2 工具链，`swiftLanguageModes: [.v5]`（并发严格性暂不 `-strict-concurrency=complete`，但新代码按 Sendable 正确写）。
- 最低 macOS 14（ADR-003，待签）；不做 13 的兼容分支。
- 只用 Apple 框架；`import` 顺序：系统框架 → 本项目模块 → 无第三方（若出现即门禁失败）。

## 2. 命名
| 规则 | 例 |
|---|---|
| 类型名带域前缀 `MS`（跨模块公开类型必须；模块内可不带） | `MSIntRect`、`AnnotationDocument`（模块内公开但被别模块用时补 `MS`） |
| 布尔用 `is/has/should` 读得通 | `isFlipped`、`shouldAutoCopy` |
| 函数名 = 动词 + 输出物，不写 `handleXxx`（除 delegate） | `pixelRect(forLogical:)`、`bake(_:source:)` |
| 事件/迁移用 `.didX/.willX` 或名词化枚举 | `selectionChanged`、`CommitIntent` |
| 禁止 `Util`/`Helper`/`Manager`/`Common` 命名 | 已有：`Registry`、`Store`、`Coordinator`、`Renderer`、`Probe` |
| 常量表集中 | 键码表 `MSHotKey.KeyCodes`、字符串表 `MSStrings`、默认值表 `AppPreferences.init()` |
| 中文文案只出现在 `MSStrings.swift` | ADR-016；grep `[\x{4e00}-\x{9fff}]` |

## 3. 文件与结构
- 单文件 ≤ 400 行（NFR-033，可机检：`wc -l`）。
- 一类型一文件为主；同域小类型（<40 行）可合并，文件名用主类型。
- 目录纪律：`MSCapture` 里不许有 `NSView`；`MSAnnotate` 里不许有 `NSWindow`（`modules.md` 的禁止项即机检项）。
- `public` 最小化：只有被别的模块用的才 public；测试用 `@testable import`（NFR-035）。

## 4. 契约与校验（边界原则）
- 内部模块之间**不做防御式校验**：类型即契约。像素坐标用 `MSIntRect`，不用 `CGRect`（ADR-013）。
- 只在系统边界校验：用户粘贴的剪贴板内容、外部拖入的图片、磁盘上的 `schemaVersion`、系统设置目录可达性、显示器布局快照与实际不一致。
- 禁止 `try!`、禁止 `fatalError`（除"逻辑不可能到达且到达即必须停"的一处，需注释说明）、禁止 `as!`。
- 不写"不可能发生"的兜底分支；要写就写 `assert` + `blocked.md` 条目号。

## 4b. 分发器必须穷举（由 2026-11-16 的事故新增）

任何"把枚举翻译成动作"的 `switch`——effect / command / notification / intent——**禁止 `default` 空转**。
反例（真出过事）：`perform(effect)` 里写 `default: break`，新增的 `.closeOverlay` 被静默丢掉，
遮罩不关、整屏吃点击，用户只能远程 ssh 杀进程。

规则：
1. 分发器不写 `default`，让"忘了处理"变成编译错误；确需兜底时写 `case .a, .b: break // 由 X 流程处理`。
2. 状态机的迁移表**可以**有 `default`，但必须是"拒绝并记录"而不是"什么都不做"（ST-001 非法迁移）。
3. `scripts/check-style.sh` 拦 `default:\s*break`。
4. 全屏模态（遮罩）必须有**至少两条**独立退出路径：键盘 Esc + 再按截图键；再加 app 失焦自动收窗兜底。

## 5. 并发
- UI 相关类型 `@MainActor`；`AnnotationDocument`/`MSCaptureFrame`/样式几何为 `Sendable` 值类型。
- 可变状态只允许在 `@MainActor` 宿主里；跨 actor 传副本不传引用。
- 热键回调、SCK 回调 → 第一时间 hop 主线程，不在回调上下文做 UI 或采集（`hotkey-and-permissions.md` §3）。
- 不用裸 `DispatchQueue.main.async` 套嵌三层以上；超过就说明状态机少了一个事件。
- 禁止新增全局单例（`App/` 组合根之外 grep `\.shared` 即警告）。

## 6. 错误与日志
- 错误用 `MSError` 分域枚举，携带 `userTextKey`（不是成品句子）+ `isRecoverable`。
- 面向用户的失败必须有可见结果（toast/引导窗），**禁止静默吞掉**（`overview.md` §6）。
- 日志走 `MSLog.logger(.capture)` 等分类，字段只有几何/耗时/标识；不含像素与文件内容（NFR-029）。
- 禁止 `print`；用 `os.Logger`（可被 `log stream` 过滤）。
- 性能标记名固定：`t.hotkey→frozen`、`t.frozen→overlay-visible`、`t.commit→clipboard-ready`、`t.crop→doc-ready`。

## 7. 依赖注入与组合根
- 能力层只依赖协议（`ScreenCapturing`、`HotKeyServing`、`MSPasteboardWriting`、`MSFileWriting`、`MSClock`、`TextMeasuring`、`AnnotationRendering`）。
- 具体实现只在 `App/AppContext` 装配；测试注入假实现（`MSTestSupport`）。
- 跨模块共享类型下沉 `MSCore`；出现"两个模块互相 import"= 设计错误，先改文档再改代码。

## 8. 测试写法
- 每个 test target 对应一个模块；测试名用中文注释 + 英文 `test_行为_条件_期望` 或 Swift 6 的 `@Test`（保持一致，用 `@Test`/`Testing` 框架优先）。
- 几何/模型用例必须无头可跑（NFR-034）；需要真实屏幕的用例统一 `@Test(.disabled(if:))` + 文档标明属实拍项（`verification.md` §3）。
- 渲染基线：`Tests/Fixtures/*.png` 由人工确认后入库；比对容差 0，失败时输出差异像素数与首处坐标。
- 属性化测试用在撤销栈（随机命令序列 → 全撤销 → 恒等）。

## 9. 文案与数字
- 用户可见串一律 key；`W×H` 用 `×`；数字用等宽读数格式（`design-system.md` §3）。
- 阈值/时长/尺寸这些数值来自 `design-system.md`（token）或 `nfr.md`（目标值），**不在代码里写裸数值**（`400`、`0.45`、`300` 之类必须有名）。

## 10. Git 与提交
见 `docs/protocol/git-and-release.md`（提交粒度、显式路径 add、文档同批）。

## 11. 评审清单（人看的 10 秒问句）

1. 这条改动的判据在哪？被观察到了吗？
2. 有没有新增未标 `待实测` 的数字？
3. 有没有 `App/` 外的全局单例 / `print` / `try!`？
4. 像素几何有没有退化回 `CGRect`？
5. 改了行为但没改文档？（搜 ID）
6. 新文件是否让某文件超 400 行？
7. 有没有"顺手统一"了别人的真源表述？
8. 新增 `public` 是否被别模块真的用到？
9. 是否有未记 `blocked.md` 的假设？
10. 本地化 key 是否齐（新中文串是否进了 `MSStrings`）？
11. 有没有新增 `default:` 空转的分发器？全屏模态有没有两条以上退出路径？
