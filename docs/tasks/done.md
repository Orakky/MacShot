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

## 本会话未做的事（写清楚，避免被当成已完成）

1. **没有任何可编译代码**：仓库当前只有文档。`make` 目标尚不存在（`AGENTS.md` §2 已注明"待 M-0 落地生效"）。
2. **未实机验证任何 macOS API 行为**：屏幕录制权限流程、`SCScreenshotManager` 延迟、贴图在全屏 Space 上的可见性、未激活窗口的键盘可达性、`RegisterEventHotKey` 冲突返回码 —— 全部标 `待实测`（现由 M-0.5 的 `T-101…T-104` 承接）。
3. **没有可视化原型稿**（HTML/图片）：目前只有 `screens.md` 的线框，是否需要视觉稿 = T-009。
4. `.gitignore` 已建立（忽略 `build/`、`.build/`、`.idea/`、`*.app`、`*.dmg`；`Tests/Fixtures/**/*.png` 例外保留）。Q-10 仍待你确认 `.idea/` 是否真按推荐忽略。
5. 文档集已提交（`4127a1e`），审查修订为第二个提交；`git push` 仍由你在终端执行。`.idea/` 已被忽略，未入库。
