# 里程碑与实施计划（M-0…M-6 唯一真源）

> 真源：里程碑的目标、准入、准出判据。待办条目在 `docs/tasks/todo.md`，本文只到"档"的粒度。
> 通则：**准出判据必须是观察到的事实**（命令输出 / 日志行 / 像素比对 / 实拍描述），不接受"代码写完了"。

## M-0 工程骨架可运行

| 项 | 内容 |
|---|---|
| 准入 | `docs/adr/README.md` 中 ADR-001/003/012 转 accepted；章程 §6 的 Q-01 已签 |
| 交付 | `MacShot.xcodeproj`（同步文件夹组）+ `Packages/MacShotKit`（10 模块 + 4 test target）+ `App/` 空壳（菜单栏 + 设置窗空壳）+ `Makefile`/`scripts`（doctor/build/test/run/dmg/check/install）+ `.gitignore` + CI-less 门禁 |
| 准出判据 | ① `xcodebuild … build` 无头成功（贴日志尾行）② 在 `App/` 放一个空 `.swift` 不改 pbxproj 即被纳入编译 ③ `swift test` 全绿（含 MSCore 几何用例）④ `make run` 出菜单栏图标且 `LSUIElement` 生效（Dock 无图标）⑤ `make check` 在无网络下跑通（ADR-015 判据归档）⑥ 依赖方向静态检查能**故意**造一条反向 import 并报错（自证可用） |
| 风险 | `stash@{0}` 的骨架是裁决前写的：**不许 pop**，只作参考；恢复前先对照 accepted ADR 逐条核对（`modules.md` §12 已列 3 处不符） |

## M-1 采集与像素正确性

| 项 | 内容 |
|---|---|
| 准入 | ADR-003/007/008/009/013 accepted；Q-01 已签 |
| 交付 | `MSCapture`（SCK 主路 + 兜底选择）、`LayoutSnapshot`、`pixelRect` 换算、权限探测与 `UI-007` 引导窗、`AnnotationDocument` schema v1、`MSCore` 几何测试卡 |
| 准出判据 | ① `capture.backend=sck` 日志出现且重启一致 ② 换算表用例全绿（scale {1,2,1.799,1.6} × 选区 5 类）③ **实拍**：1px 边缘线条导出图与屏幕颜色一致（`V-002`）④ 撤销授权后首启出现引导窗且"打开系统设置"真的跳到该面板 ⑤ `t.hotkey→frozen`/`t.frozen→overlay-visible` 实测数值写进 `done.md`（NFR-001）⑥ schema v1 冻结（此后只增不改，`ADR-009` 判据 3）⑦ 会话后内存回基线（NFR-008） |
| 明确不含 | 遮罩 UI、任何标注绘制 |

## M-2 选区与提交闭环

| 项 | 内容 |
|---|---|
| 准入 | M-1 准出全绿；ADR-002/010/014 accepted；Q-02/05/09 已签 |
| 交付 | `MSOverlay`（遮罩 + 冻结帧显示 + 选区 + 读数 + 把手）、`MSSession` 状态机 + `SessionCoordinator`、`CommitIntent` 路由、`MSExport`（剪贴板 + DPI）、`MSHotKey` |
| 准出判据 | ① **实拍**：播放动画时截图，背景全程不变（`ADR-008` 判据 1）② `ST-001` 用例表逐条通过（含 5 条非法迁移被拒绝）③ 拖 100×100（2x 屏）读数 200×200 且与 `cgImage.width` 一致 ④ `Esc` 后剪贴板哨兵未被改（FR-SESS-002）⑤ 提交后 `NSWorkspace.frontmostApplication` 未变（FR-SESS-003，键盘焦点风险的验收点：若"未激活却收不到键"，此条不可能绿）⑥ `V-003` 表示矩阵表实测填完（ADR-014 转 accepted）⑦ 会话中拔屏不崩（NFR-016） |
| 里程碑含义 | **这一档结束就能替代"系统截图 + 预览裁剪"**（vision S1 的前半） |

## M-3 贴图

| 项 | 内容 |
|---|---|
| 准入 | M-2 全绿；Q-06/13 已签 |
| 交付 | `MSPin`（`PinContent`、level、跨 Space、缩放、透明、拖拽、关闭、`PinRegistry`）、`F3` 剪贴板贴图、UI-003 |
| 准出判据 | ① **实拍**：全屏 Space 的 Safari 之上贴图仍可见可点（FR-PIN-001，若失败即 ADR-019 触发）② 出现/关闭不改前台（FR-PIN-004）③ 滚轮缩放以指针为锚（矩阵单测）④ `F3` 从浏览器复制图后贴出，尺寸与源图一致 ⑤ `⌘`+滚轮透明度且导出恒不透明 ⑥ 10 张贴图的内存读数进 `done.md` 并对照 NFR-005 |

## M-4 标注与再编辑

| 项 | 内容 |
|---|---|
| 准入 | M-3 全绿；Q-03/11/12 已签；`ADR-011` accepted |
| 交付 | `MSAnnotate` 全量（9 件工具、样式、命中、撤销栈、渲染器三 intent）、UI-002 工具条、贴图内再编辑（UI-004）、`FR-ANN-012` 的"清空 + 提示"行为 |
| 准出判据 | ① 8/9 件工具 × 3 intent 基线 PNG 逐像素一致（容差 0）② 拖拽 100 次 → 撤销栈 1 条 ③ `E` 进编辑 → 画箭头 → `Enter` → 同 id 贴图含箭头且 `elements.count` +1 ④ 改选区尺寸 → 标注清空且警告出现（Q-11）⑤ 荧光笔 `multiply` 在屏上与导出同色 ⑥ NFR-005 三项读数达标或触发回 Q-12（**这一档是 D-04 的真验收**）⑦ VoiceOver 不可读范围书面清单（NFR-026） |

## M-5 设置、导出与可发布内核

| 项 | 内容 |
|---|---|
| 准入 | M-4 全绿；Q-02 定稿 |
| 交付 | UI-005 设置窗（热键/提交动作/导出目录与模板/外观/权限状态）、`⌘S`/`⌘⇧S`、`AppPreferences` 全字段、菜单项齐全、本地化表（ADR-016） |
| 准出判据 | ① 每个设置项：改动 → 落盘 → 即时生效（无重启）→ 重启后仍在（逐条实测清单）② 重绑热键后新键生效且旧键不再触发（FR-HOT-002）③ 免面板直存连续 10 次无重名覆盖 ④ 命名模板预览与实际文件名一致 ⑤ 中文文案只在 `MSStrings.swift`（grep 门禁）⑥ 对比度脚本 ≥ 4.5:1 全绿（NFR-024） |

## M-6 打磨、发布与指标

| 项 | 内容 |
|---|---|
| 交付 | `make dmg` + ad-hoc 签名产物、兼容矩阵实测填满（NFR §5）、性能表（NFR §1/§2）、`scripts/usage-report.sh`（vision §4 的 G-01…G-05）、README 使用与快捷键说明、`docs/runbook/troubleshooting.md` 回填真实问题 |
| 准出判据 | ① DMG 在本机安装后全新用户流程可用（`tccutil reset` 起走一遍）② 兼容矩阵无"待实测"空格（有则发布说明如实缩小支持范围）③ G-01/G-02 在你机器上连续 5 天成立 ④ NFR §1/§2 每条有实测数值 ⑤ 已知限制清单成文（键盘不闭环、VoiceOver 范围、macOS 13 不支持、ad-hoc 不能直发他人） |

## 排期与顺序的理由（为什么先 M-1 后 M-2）
像素正确性一旦先被遮罩 UI 掩盖，之后每次改遮罩都会重新引入尺寸 bug；把"采集 + 几何"单独跑绿，后面所有屏的判据才有可信基线。这也是 `vision.md` S1 与 S2 的先后顺序依据。

## 波次与并行
一档一个波次，波次内按文件域并行（`docs/protocol/agent-playbook.md` §3）。跨模块接口变更**必须同波**改 `modules.md` 与调用方，禁止"下波再补"。
