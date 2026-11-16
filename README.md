# MacShot

macOS 原生截图工具：**快速截图 → 标注 → 贴图置顶 → 一键进剪贴板**。形态参考 Snipaste，技术栈 Swift + AppKit。

## 当前状态：文档裁决期（无代码）

| 层 | 状态 |
|---|---|
| 范围裁决 D-01…D-04 | ✅ 已签（见下表） |
| 需求清单（P0 见 §0 统计，每条带判据） | ✅ 已成文，待逐条 `accepted` |
| 技术架构（8 份）+ ADR（16 条：4 accepted / 12 proposed） | ✅ 已成文，**proposed 项不可落地为代码** |
| 设计原型（token + 逐屏线框 + 状态机 + 键位） | ✅ 已成文，待裁决 |
| 里程碑 M-0…M-6 + 待办/已办/卡点台账 | ✅ 已成文 |
| 工程骨架、构建脚本、任何 `.swift` | ⛔ 未开始（`docs/tasks/todo.md` 第 0 档仍红，硬约束见 `docs/README.md` §4） |

已裁决的四条：

| | 结论 | 代价 |
|---|---|---|
| D-01 | 首版只做四大件，P0 必须能映射到某一件 | 窗口自动识别、历史、分组、水印等全部 P1/P2 |
| D-02 | 本机直装 + ad-hoc 签名，不启用沙盒 | 不能直接发给别人（无证书、无公证） |
| D-03 | Xcode 工程（同步文件夹组）+ 本地 SPM 多模块包 | agent 不许改 `project.pbxproj` |
| D-04 | 贴图携带**可编辑标注文档**（保留矢量层） | schema 第一天冻结、两套宿主共用渲染器、内存一档代价（NFR-005 是回退阀）。注意：这在 Snipaste 属付费 PRO 能力，见 `docs/reference/snipaste-gap.md` §4 |

## 我要看什么（按裁决顺序）

1. `docs/charter.md` §6 —— **Q-01…Q-15 待你签字**，这是解锁编码的唯一门槛（Q-15 建议先做 M-0.5 探针再签）
2. `docs/adr/README.md` —— 12 条 `proposed` 决策（含每条的否决方案与翻案条件）
3. `docs/requirements/requirements.md` —— P0 清单与判据（条数只在 §0 统计）；§3 是 P1
4. `docs/design/screens.md` —— 逐屏线框（遮罩 / 工具条 / 贴图 / 再编辑 / 设置 / 菜单 / 权限窗）
5. `docs/plan/roadmap.md` + `docs/tasks/todo.md` / `done.md` / `blocked.md`

协作方式（人 + agent）写在 `AGENTS.md` 与 `docs/protocol/agent-playbook.md`。

## 目录

```
AGENTS.md                 agent 入口（纪律 + 命令 + 领活）
docs/
  charter.md              最高真源：范围 / 术语 / 模块名 / ID 规则 / 待裁决
  README.md               文档地图 + 单一真源分配 + 冲突消解序
  requirements/           vision · requirements(P0/P1/P2) · nfr
  architecture/           overview · modules · capture · overlay · annotate · pin · export · hotkey
  adr/                    README(索引) · ADR-001…016
  design/                 design-system · screens · state-machines · keymap
  plan/  tasks/           roadmap · todo · done · blocked
  protocol/               agent-playbook · coding-conventions · verification · git-and-release
  runbook/                setup · build-and-verify · permissions-tcc · troubleshooting
  reference/              snipaste-gap（全部带出处）
  templates/              task-card · adr · spec-doc
spikes/                   未裁决代码停放处（当前为空；一版骨架在 stash@{0}）
App/  Config/  Packages/  Makefile  scripts/     ← M-0 才创建
```

## 计划中的命令（M-0 落地后生效）

```sh
make doctor  build  test  run  dmg  install  check
```
构建与验证目标的具体契约已写成规格：`docs/runbook/build-and-verify.md`。

## 已知限制（现在就写清，避免以后当惊喜）

- 最低 macOS 14（`ADR-003` 待签）；macOS 13 及以下不支持。
- 首版键盘-only 链路**不闭合**（选区方向键微调在 P1，`NFR-022`）。
- VoiceOver 对自绘遮罩/贴图的支持首版不完整，只交付"不可读范围清单"（`V-028`）。
- ad-hoc 签名 ⇒ 不能直接分发；重装后可能需要重新授予屏幕录制权限（`P-002`）。
- 首版不落盘任何截图（无历史），贴图内的再编辑内容在退出后丢失（Q-06 推荐 A，`UI-003` 有"未导出"标记）。

环境事实与验证方式见 `docs/runbook/setup.md`；所有性能数字目前是**目标值（待实测）**，实测数据集中在 `docs/tasks/done.md`。
