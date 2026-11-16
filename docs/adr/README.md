# ADR 索引（架构决策记录）

> 规则：一条决策一个文件，文件名 `ADR-<序号>-<kebab-slug>.md`，模板见 `docs/templates/adr.md`。
> **状态 `proposed` 的决策不得落地为代码**（章程 §7）。用户签字后改为 `accepted`。
> 待裁决的架构问题就登记在本表（不另开清单）：凡状态列为 `proposed` 的行，都需要用户点头。
> 当前计数（2026-11-16）：**accepted 8**（001/003/004/005/006/007/008/010）· **proposed 8**（002/009/011/012/013/014/015/016）。

| ID | 标题 | 状态 | 决定什么 | 被谁引用 |
|---|---|---|---|---|
| ADR-001 | 构建体系：Xcode 工程（同步文件夹组）+ 本地 SPM 多模块包 | **accepted**（D-03） | agent 如何增删源文件、如何无头构建与测试 | `docs/protocol/agent-playbook.md`、`docs/runbook/build-and-verify.md` |
| ADR-002 | UI 技术栈：AppKit 优先，SwiftUI 只进设置面板 | proposed | 遮罩/贴图/画布的窗口与事件模型能不能用 SwiftUI | `docs/architecture/overview.md` |
| ADR-003 | 最低系统版本 macOS 14 Sonoma（= 章程 Q-01） | **accepted**（2026-11-16） | 可用 API 面、CI 矩阵、兼容声明 | `docs/requirements/nfr.md` |
| ADR-004 | 非沙盒 + ad-hoc 签名 + 本机直装（D-02） | **accepted** | entitlements、TCC 授权流程、导出目录自由度 | `docs/runbook/permissions-tcc.md` |
| ADR-005 | 贴图携带可编辑标注文档，而非烘焙位图（D-04） | **accepted** | MSPin/MSAnnotate 接口、内存、缩放无损 | `docs/architecture/pin-window.md` |
| ADR-006 | 首版范围＝四大件，P0 需映射到件（D-01） | **accepted** | 需求准入 | `docs/requirements/requirements.md` |
| ADR-007 | 采集后端：`SCScreenshotManager` 单帧主路（不做实时流） | **accepted**（2026-11-16；兜底是否保留待确认） | 权限模型、单屏/多屏、性能、弃用风险 | `docs/architecture/capture-pipeline.md` |
| ADR-008 | 遮罩实现：整屏冻结快照 + 全屏透明窗（不做实时流） | **accepted**（2026-11-16） | "先冻结后选区"的语义、延迟、内存上限 | `docs/architecture/overlay-and-selection.md` |
| ADR-009 | 标注文档编码与版本：带 `schemaVersion` 的 JSON（M1 出口冻结） | proposed（已加展开说明待你判） | `.macshot` 格式、迁移策略、diff 可读性 | `docs/architecture/annotate-model.md` |
| ADR-010 | 全局热键：Carbon `RegisterEventHotKey`；辅助功能权限策略放开 | **accepted**（2026-11-16） | 权限、可靠性、可发现性、未来替代路径 | `docs/architecture/hotkey-and-permissions.md` |
| ADR-011 | 撤销栈：命令式 + 拖拽合并（一次拖拽 = 一条记录） | proposed | MSAnnotate 历史模型与内存 | `docs/architecture/annotate-model.md` |
| ADR-012 | 模块切分与依赖方向（10 模块，见章程 §4） | proposed | 新增代码放哪、谁可以 import 谁 | `docs/architecture/modules.md` |
| ADR-013 | 坐标系规约：逻辑=AppKit 全局 y 向上；像素=显示器本地 y 向下 | proposed | 全部几何函数签名；违反即 bug | `docs/architecture/capture-pipeline.md` |
| ADR-014 | 剪贴板表示：PNG + TIFF 双表示 + DPI 元数据（= 章程 Q-04） | proposed | 跨应用粘贴兼容性、体积 | `docs/architecture/export-clipboard.md` |
| ADR-015 | 零第三方依赖 + 无 brew 环境下的本地门禁脚本 | proposed | 能否引入 swiftlint/xcodegen；`scripts/check.sh` 内容 | `docs/protocol/coding-conventions.md` |
| ADR-016 | 本地化：英文常量表 + 中文文案，暂不引入 String Catalog | proposed | 文案改动流程 | `docs/protocol/coding-conventions.md` |

## 待补（已知的未知，写清楚比留空好）

| 占位 | 议题 | 触发时机 |
|---|---|---|
| ADR-017 | 窗口/元素自动识别的实现路径（`CGWindowList` vs 无障碍 API vs SCK 窗内容） | FR-CAP-011 开工前（P1） |
| ADR-018 | 截图历史的存储格式与上限 | Q-06 选 B 时 |
| ADR-019 | 贴图层（level）具体数值与与系统 HUD/全屏视频的关系 | FR-PIN-001 实跑发现不满足时 |
| ADR-020 | 开机自启（`SMAppService`）与 ad-hoc 签名的兼容性 | FR-SET-011 开工前 |
| ADR-021 | 高斯模糊实现路径：`CIFilter` vs 手写可分离核（一致性/性能/版本差异） | `ADR-009` accepted 后、M-4 开工前（`annotate-model.md` §5.4） |
| ADR-022 | **实时录制**（录屏/GIF）是否解禁与其资源模型 —— 需要 `SCStream` 常驻、编码、体积、音频权限 | 章程 **Q-17** 选 B/C 时才写；选 A 则本行标 `dropped` |
