# MacShot 文档地图

> 本文件是文档索引与"单一真源"分配表。**新来的 agent 按 §1 顺序读，不要漫游。**
> 更新规则：新增文档必须同时在本表登记一行；一条事实搬家时，旧家留一行 `见 X#ID` 指针。

## 1. 推荐阅读顺序（5 分钟上岗）

1. `AGENTS.md`（根）——纪律与命令
2. `docs/charter.md` ——范围、术语、模块名、ID 规则、裁决状态
3. `docs/requirements/requirements.md` ——P0 清单与判据（条数只在 §0 维护）
4. `docs/plan/roadmap.md` → `docs/tasks/todo.md` ——领当前这一档活
5. 干活时按需读：`docs/architecture/<对应模块>.md`、`docs/design/screens.md`、`docs/protocol/verification.md`

## 2. 文档树与真源分配（2026-11-16 落盘实况）

| 路径 | 内容 | 真源地位 | 状态 |
|---|---|---|---|
| `AGENTS.md` | agent 入口：纪律、命令、领活、禁做 | 纪律摘要（正文 `protocol/agent-playbook.md`） | 已落 |
| `charter.md` | 范围/术语/命名/ID/D-01…D-04/Q-01…Q-15 | **最高** | 已落，§6 待签字 |
| `README.md`（本文件） | 文档地图、冲突消解序、当前阶段 | 索引 | 已落 |
| `requirements/vision.md` | 定位、3 场景、G-01…G-05 成功指标、反定位 | 愿景 | 已落，待裁决 |
| `requirements/requirements.md` | FR P0（条数见 §0）/ P1 / P2 / 不做 | 功能需求 | 已落，逐条待转 accepted |
| `requirements/nfr.md` | NFR-001…036（全部"目标值待实测"） | 非功能需求 | 已落，§9 待签字 |
| `adr/README.md` | ADR 索引 + 状态（4 accepted / 12 proposed）+ 待补占位 | 决策状态 | 已落 |
| `adr/ADR-001…016-*.md` | 16 条决策正文（含否决方案与翻案决策门） | 决策正文 | 已落，proposed 待签 |
| `architecture/overview.md` | 进程/窗口模型、分层、数据流、并发、启动退出、失败模型、可测接缝 | 架构总览 | 已落 |
| `architecture/modules.md` | 10 模块职责 + API 草图 + 依赖图 + 骨架差异 | 模块边界 | 已落 |
| `architecture/capture-pipeline.md` | 冻结→选区→裁剪；后端表；像素对齐；权限探测 | 采集机制 | 已落 |
| `architecture/overlay-and-selection.md` | 遮罩窗、渲染策略、事件路由、键位、放大镜契约 | 遮罩机制 | 已落 |
| `architecture/annotate-model.md` | 文档 schema、kind 表、渲染器三 intent、撤销、Q-11 行为 | 标注模型 | 已落 |
| `architecture/pin-window.md` | 窗属性与 level、`PinContent`、缩放/透明、再编辑、内存、注册表 | 贴图机制 | 已落 |
| `architecture/export-clipboard.md` | 剪贴板表示、色彩与 DPI、命名模板、`CommitIntent` | 导出机制 | 已落 |
| `architecture/hotkey-and-permissions.md` | Carbon 实现要点、权限地图、探测与引导、默认键 | 热键与权限 | 已落 |
| `design/design-system.md` | 颜色/字体/间距/圆角/图标/动效/光标 token | 视觉 token | 已落，数值待裁决 |
| `design/screens.md` | UI-001…UI-009 线框 + 元素规格 + 屏↔需求对照 | 屏幕规格 | 已落，待裁决 |
| `design/state-machines.md` | ST-001…ST-006 迁移表与非法迁移 | 状态机 | 已落 |
| `design/keymap.md` | 键位总表（含 Snipaste 对应与出处） | 键位 | 已落，默认值随 Q-02 |
| `plan/roadmap.md` | M-0…M-6 准入/交付/准出判据 | 里程碑 | 已落 |
| `tasks/todo.md` | 第 0 档裁决项 T-001…009 + 编码档 T-010… | 待办 | 已落，第 0 档全红 |
| `tasks/done.md` | E-001…E-012 证据 + "本会话未做的事" | 已办 | 已落 |
| `tasks/blocked.md` | B-001…B-013 + 已解 3 条 | 卡点 | 已落 |
| `protocol/agent-playbook.md` | 上岗检查、任务卡、域并行、DoD、反模式、半态、只读 agent 分工 | 协作方式 | 已落 |
| `protocol/coding-conventions.md` | 命名/结构/契约/并发/日志/DI/测试/文案 + 评审 10 问 | 代码规范 | 已落 |
| `protocol/verification.md` | V-001…V-035 + 剪贴板矩阵 + 判据反模式 | 验收 | 已落 |
| `protocol/git-and-release.md` | 提交粒度、版本号、产物与发布检查表、回滚 | Git 与发布 | 已落 |
| `runbook/setup.md` | 零依赖环境基线 + 接手清单 + 实测记录 | 环境 | 已落 |
| `runbook/build-and-verify.md` | make 目标契约 + 6 条门禁脚本规格 + 排查顺序 | 构建 | 已落（目标本身待 M-0 存在） |
| `runbook/permissions-tcc.md` | 授权流程、ad-hoc 坑、复位手段、实测记录 | 权限 | 已落 |
| `runbook/troubleshooting.md` | P-001…P-015 问题库骨架 + 追加模板 | 问题库 | 已落（真实根因待实测追加） |
| `reference/snipaste-gap.md` | Snipaste 事实对照（三分法：官方/推断/未找到出处） | 参考，**非真源** | 已落 |
| `templates/task-card.md` | 六项必填任务卡 + 粒度参考 | 模板 | 已落 |
| `templates/adr.md` | ADR 模板（含"否决方案+翻案决策门"要求） | 模板 | 已落 |
| `templates/spec-doc.md` | 模块/屏幕/状态机共用规格模板 + 反面清单 | 模板 | 已落 |
| `../prototypes/index.html` | **可操作原型**（9 屏共用一套标注文档；拖选区/画标注/贴出/缩放/取色都能真跑） | 校对辅助，**非真源**（规格以 `design/screens.md` 为准） | 已落（E-014） |
| `../spikes/README.md` | 未裁决代码停放规则 + `stash@{0}` 说明 | **非真源** | 已落 |
| `../App` `../Config` `../Packages` `../Makefile` `../scripts` | 工程骨架 | 代码 | **不存在**（M-0，第 0 档红） |

## 3. 冲突消解

两处说法不一致时：`charter.md` > `adr/README.md`(accepted) > `requirements.md` / `nfr.md` > `architecture/*` > `design/*` > `plan|tasks` > `prototypes|reference`。
发现冲突 = 立即写进 `docs/tasks/blocked.md` 一条并停下问用户；不许"顺手统一"（`AGENTS.md` §3.9）。
机检：`scripts/check-docs.sh` 要求"所有 `见 X#ID` 可解析"，解析失败即门禁红（`build-and-verify.md` §2）。

## 4. 当前阶段与解锁条件

**文档裁决期。** 解锁编码需要同时满足：
1. `charter.md` §6 的 Q-01…Q-15 全部签字；
2. `adr/README.md` 无 `proposed` 行；
3. `requirements.md` §1 的 P0 行状态从 `待裁决` 转 `accepted`；
4. `nfr.md` §9 的 4 项取舍确认。
对应台账条目 `T-001…T-009`（`tasks/todo.md` 第 0 档）。任一未满足 ⇒ 不建工程骨架、不写 `.swift`。

## 5. 已知文档缺口（诚实登记，不是遗漏）

| 缺口 | 处理归属 |
|---|---|
| 原型能证伪的只有"几何/像素/交互手感"；**证伪不了** TCC 授权、window level 盖全屏、未激活窗收键（那三项是 T-101/T-102/V-021 的活） | 已在 `prototypes/index.html` 右栏逐项标明"原型态 vs 待实测" |
| ADR-017…021 正文（元素识别、历史存储、贴图 level、自启、模糊核） | 各自触发时机见 `adr/README.md` 待补表 |
| `MSSettings` 默认值全字段表（现散在 `keymap.md`/`export-clipboard.md`） | M-0 的 `T-016` 一并收口 |
| 英文文案对照表（`MSStrings` 的 en 列） | M-5 `T-070…` |
| 兼容矩阵 15 格、性能表、剪贴板矩阵全空 | M-1/M-2/M-6 实测轮次（`V-019`/`V-003`） |
