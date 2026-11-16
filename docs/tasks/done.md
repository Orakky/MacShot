# 已办台账（附证据）

> 规则：**没有证据不写已办**。证据 = 命令输出尾行 / 文件路径 / 读数 / 实拍描述。日期用绝对日期。
> 已完成条目的正文迁到所属文档，本表只留一行 + 指针。

## 2026-11-16 文档裁决期（Wave 0：定范围）

| ID | 条目 | 证据 |
|---|---|---|
| E-001 | 环境事实核实 | `swift --version` → `Apple Swift version 6.2.4 … Target: arm64-apple-macosx15.0`；`xcodebuild -version` → `Xcode 26.3 (17C529)`；`xcrun --sdk macosx --show-sdk-version` → `26.2`；`sw_vers` → `15.7.4 (24G517)`；`ls /opt/homebrew/bin/brew` → `No such file or directory`；`security find-identity -v -p codesigning` → `0 valid identities found`。这些事实直接生成了 ADR-003/004/015 的结论 |
| E-002 | 4 项范围裁决取得（D-001…D-004） | 用户在会话中选择：只做四大件最小闭环 / 本机 ad-hoc 直装 / Xcode 工程 + 本地 SPM / 贴图携带可编辑标注层。已落纸 `docs/charter.md` §1 |
| E-003 | 过早写下的骨架收起（不是删除） | `git stash push -u -m "architecture-spike: …" -- Packages App` → `git stash list` = `stash@{0}: On main: architecture-spike…`；`git stash show --include-untracked --stat` = `9 files changed, 874 insertions(+)`；`find App Packages -type f` → 空。落纸为 `docs/architecture/modules.md` §12 的 3 处不符与 `T-018` 处置项 |
| E-004 | 文档宪法与地图落地 | `docs/charter.md`（范围/术语/模块/ID/Q 表/非谈判项）、`docs/README.md`（真源分配 + 冲突消解序 + 当前阶段判据）、`AGENTS.md`（纪律 + 命令 + 领活） |
| E-005 | 需求清单可裁决版落地 | `docs/requirements/requirements.md`：P0 带判据、P1、P2 与"明确不做 6 项"；准入纪律"无归属大件即降 P1"（`ADR-006`）。条数初稿写错（32/34），2026-11-16 审查订正为 §0 的 33/27，并把计数收敛到 §0 单一来源 |
| E-006 | Snipaste 事实核查（一手来源） | `docs/reference/snipaste-gap.md`，7 节全部带出处（docs.snipaste.com 的 getting-started / key-bindings / PRO / FAQ / Troubleshooting / Changelog + developer.apple.com 的 SCStream / SCScreenshotManager / CGWindowListCreateImage / CGDisplayCreateImage）；由后台研究 agent 取得（`【示例】研究助手`，32 次工具调用） |
| E-007 | 研究结论**推翻**了我先前 3 处假设并据此订正 | ① 取色不是 `F4`：官方是"放大镜可见时按 `C`"→ 改 `requirements.md#FR-CAP-012/013/014`、`keymap.md` §1/§2（原先写的"⇧+方向=10px"也是杜撰，官方是 `⌘`/`⇧`+方向做扩大/缩小）② 序号徽章与"二次编辑"是 Snipaste **PRO** 功能 → `charter.md` D-04 行加知情提示 + 新增 Q-12 ③ 剪贴板 PNG/TIFF 双表示**无官方出处** → Q-04 依据改为目标应用实测矩阵（`ADR-014`）④ 附加：橡皮擦是免费档功能而我漏了 → Q-03 从 8 件改 9 件 |
| E-008 | 架构层落地 8 份 | `docs/architecture/{overview,modules,capture-pipeline,overlay-and-selection,annotate-model,pin-window,export-clipboard,hotkey-and-permissions}.md`；含依赖图、坐标契约、渲染器三 intent、贴图 level 风险、内存粗算（4K 整屏 3840×2160×4 ≈ 33MB 为**粗算待实测**） |
| E-009 | ADR 16 条落地（4 accepted / 12 proposed） | `docs/adr/README.md` + `ADR-001`…`ADR-016`；每条含"已考虑并否决的方案 + 什么证据会翻案"（决策门），非只写结论 |
| E-010 | 设计层落地 4 份 | `docs/design/{design-system,screens,state-machines,keymap}.md`；UI-001…UI-009 逐屏线框 + 元素规格表 + 屏↔需求对照表（含已发现的缺口：多屏切换、贴图分组）；ST-001…ST-006 迁移与非法迁移用例 |
| E-011 | NFR 与愿景落地 | `docs/requirements/nfr.md`（NFR-001…036，全部标"目标值待实测"）、`docs/requirements/vision.md`（3 场景 + 5 个可观察成功指标 G-01…G-05） |
| E-012 | 计划与台账落地 | `docs/plan/roadmap.md`（M-0…M-6 准入/交付/准出判据）、`docs/tasks/todo.md`（第 0 档 T-001…009 为裁决项；编码档全部标 `待裁决`）、本文件 |
| E-013 | 2026-11-16 文档审查与补充（第二次通读，按"可证伪事实"核对） | 订正 6 类问题：① **NSWindow level 升序写错 2 处**（`overlay-and-selection.md` §1 把 `.screenSaver` 说成低于菜单栏；`pin-window.md` §1 把 `.modalPanel`(8) 排在 `.mainMenu+1`(25) 之后）② **需求计数错**：实际 P0=33、P1=27（原写 32/34），且 charter/README/ADR-006/done 各自复制 → 改为只引用 `requirements.md` §0 ③ **2 条判据不可执行**：FR-PIN-003"不同倍率同位置像素比对"、FR-ANN-006"屏上与导出逐像素一致" ④ **FR-SESS-003 把实现手段当需求**（"不激活 app"）→ 改为行为判据 + 新增 **Q-15** ⑤ 协议名不统一（overview 的 `Clock/FileSystem` vs modules 的 `MSClock/MSFileWriting`）⑥ `.gitignore` 缺 `.build/`（`swift test` 会在包目录生成）。**补充**：M-0.5 技术探针（`T-101…T-104`）、`B-014`/`B-015`、`design-system` 新增把手 token。证据：`git diff 4127a1e -- docs` |

## 2026-11-16 原型轮（T-009 → T-060）

| ID | 条目 | 证据 |
|---|---|---|
| E-014 | 可操作原型 `prototypes/index.html`（单文件、零依赖、零网络资源） | **量测到的事实**（浏览器内程序化驱动，非目测）：① `pixelRect({100.5,80.25,200.5,120.25})` @2x → `{201,161,401,240}`；naive `round(h×2)` 会给 241，差 1px —— ADR-013 的"两边分别取整"在原型里可见 ② 合成拖拽 (600,400)→(820,560) 落在既有选区内 → mode=`move`（判定顺序对），读数 `860×500 @2x` 与裁剪像素 `{500,340,860,500}` 同源 ③ 画箭头写入文档坐标 `(60,60)-(420,240)`（设备像素，y 向下）④ `⌘P` 提交后 `pin.elements=1` —— **D-04 的链路在原型里真的带过去了** ⑤ 贴图 zoom=2.5 时位图 backing 恒 `860×500`（不重采样）、矢量 backing `1075×625`＝860×2.5（按倍率重绘）、`image-rendering:pixelated` 生效 → 放大后"位图成方块、标注仍锐利"是可看到的 ⑥ 取色对假桌面真实采样命中 `#E83347`（就是那块饱和红）⑦ 9 屏 `paint()` 遍历无异常，把手计数 8。**修掉两个原型自身的 bug**：标注层 backing 多乘了一次 dpr（元素只会出现在左上 1/4）、贴图矢量层倍率算错（等于演示不出 D-04 的收益）；`.stage` 宽度由内容反推导致坍缩，改为固定 1200×760 逻辑舞台 + 外层 `transform:scale`。**原型不能证明的**：TCC 授权、window level 能否盖全屏、未激活窗口能否收键 —— 仍是 T-101/T-102/V-021 的活，右栏已逐屏标注"原型态 vs 待实测" |
| E-015 | 截图自查未做成 | `take_screenshot` 返回 `NATIVE_BROWSER_VIEWPORT_UNAVAILABLE … viewport=0x0, visible=false` → 内嵌浏览器无可视口，故改用 `evaluate_script` 做数值与路径核对。**视觉效果需你在真浏览器里打开这个文件看**，我没有目测过 |

## 2026-11-16 需求变更（用户提出"截图后可直接置顶"）

| ID | 条目 | 证据 |
|---|---|---|
| E-016 | 把"贴出"提升为一等出口：新增 `FR-PIN-018`、Q-05 推荐档由"复制"改为"贴出"、工具条主按钮与键位重排（`Enter`＝贴出、`⌘C`/`⌥Enter`＝复制、`⌘P` 保留）、默认出口改为查 `commitBehavior` 而非写进枚举语义 | 原型内程序化验证：按钮顺序读数 `贴出Enter* \| 复制⌘C \| 保存⌘S \| ✕`（`*`＝实底主按钮）；`Enter` → `pins 0→1`、`screen=UI-003`、选区已收；`⌥Enter` → `pins 1→1`（不新增贴图）且会话结束；设置默认档读数 `贴出*`。文档同步：`requirements.md` §0 计数 33→34、`charter.md` Q-05、`keymap.md` §2、`overlay-and-selection.md` §5、`export-clipboard.md` §5、`screens.md#UI-002`、`vision.md` S1、`verification.md` V-036 |

## 2026-11-16 架构裁决（第二批签字）

| ID | 条目 | 证据 / 后果 |
|---|---|---|
| E-017 | 签下 **ADR-003**（macOS 14）、**ADR-007 + ADR-008**（冻结快照、不做实时流）、**ADR-010**（Carbon 热键 + 辅助功能权限策略放开）；`adr/README.md` 计数改为 accepted 8 / proposed 8；章程 Q-01 标已签；`T-001` 转已办、`T-007` 缩到剩余 8 条 | 你的原话"采集的时候冻结快照，暂时不需要考虑实时"命中的是 ADR-008，ADR-007 是其下游结论，已在 ADR-007 顶部记明这一映射，并留了一个未决小格（是否保留 CG 兜底路径） |
| E-018 | **纠正一处权限误解并落纸**：辅助功能权限**不能**读取屏幕内容，录屏只认屏幕录制权限 | 写在 `ADR-010` 裁决记录 + `hotkey-and-permissions.md` §4；新增 **Q-16**（辅助功能权限何时索取，推荐 P1 再用时索取）与 **Q-17**（"实时录制"目前属"明确不做"，要不要解禁；`ADR-022` 占位） |
| E-019 | **ADR-013 的算术自我纠正**：用 `ROUND_HALF_UP`（等价 Swift `.rounded()`）实测 20 组坐标 | 结论：**2x 下"两边分别取整"与 naive 完全一致**；差 1px 出现在 **1x + 半点坐标**（x=100.5,w=200.5 → 201 vs **200**；x=0.5,w=100.5 → 101 vs **100**；x=64.5,w=37.5 → 38 vs **37**）与 **1.799x**（361 vs **360**）。本 ADR 早先"这是为非整数缩放准备的"表述不准，已在 ADR-013 与 `capture-pipeline.md` §4 改正：它是每次选区都要走的路径，不是外接屏特例 |
| E-020 | ADR-009 / ADR-013 补"展开说明"章节供你裁决 | ADR-009 展开：这条实际决定 ①内存类型形状 ②将来序列化的字节契约 ③版本兼容策略三件事，JSON 换回来的是"夹具能手写 + 出问题能 `cat` + diff 可读"，代价约 3–4KB/20 元素（估算待实测）；并把问题收敛成两个：是否接受字段只增不改语义、是否接受 M-1 冻结 |

## 尚未完成 / 未验证（写清楚，避免被当成已完成）

1. **没有任何可编译代码**：仓库只有文档 + 一个 HTML 原型。`make` 目标尚不存在（`AGENTS.md` §2 注明"待 M-0 落地生效"）。
2. **未实机验证任何 macOS API 行为**：屏幕录制权限流程、`SCScreenshotManager` 延迟、贴图在全屏 Space 上的可见性、未激活窗口的键盘可达性、`RegisterEventHotKey` 冲突返回码 —— 全部标 `待实测`（现由 M-0.5 的 `T-101…T-104` 承接）。
3. **原型的视觉观感未经目测**：E-015 说明了原因（无可视口）。它证明了数学与状态路径，不等于"看起来对"——第一次在真浏览器里打开时请顺手校对：工具条是否压住选区内容、贴图投影与角标位置、设置窗 460pt 是否够用。
4. `.gitignore` 已建立（忽略 `build/`、`.build/`、`.idea/`、`*.app`、`*.dmg`；`Tests/Fixtures/**/*.png` 例外保留）。Q-10 仍待你确认 `.idea/` 是否真按推荐忽略。
5. 提交记录：`4127a1e`（文档集）→ `c6f819b`（审查修订）→ 本轮原型为第三个提交；`git push` 由你在终端执行。
