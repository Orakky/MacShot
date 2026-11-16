# ADR-012 模块切分与依赖方向

状态：**proposed** 日期：2026-11-16 相关：ADR-001、`docs/charter.md` §4、`docs/architecture/modules.md`

## 决策（建议）
10 个包内模块 + `App/` 组合根，依赖方向单向（`modules.md` §11 的图）。`MSCapture` 不依赖任何 UI；`MSAnnotate` 不 import `NSWindow`；逻辑代码一律可在 `swift test` 下跑。

## 为什么是这个粒度
| 选择 | 理由 |
|---|---|
| 遮罩（`MSOverlay`）与采集（`MSCapture`）分开 | 采集的正确性测试不需要窗口；并行开发时两者文件域天然不重叠 |
| 标注模型（`MSAnnotate`）与宿主（`MSOverlay`/`MSPin`）分开 | D-04 要求"一套渲染器三处宿主"，混在一起就必然出现贴图另写一套绘制 |
| `MSSession` 单独存在 | 状态机是 P0 判据最密集的地方（ST-001…006），必须能无头穷举 |
| 不为"编辑器"单开模块 | D-04 已把再编辑放进贴图窗；再开一个模块等于给 `FR-QE-001` 复活留门 |

## 已考虑并否决的方案
- **单一 target（全放一个模块）**：并行开发必冲突，且 `swift test` 会拖进 UI 依赖。翻案条件：模块间编译耦合导致构建时间 >3× 单模块（实测，`doctor` 里量）。
- **按 UI 屏切模块（`CaptureUI`/`PinUI`）**：会把几何与渲染切碎到两处，跨屏一致性（"屏上所见 = 导出所得"）失去单一归属。
- **把 `MSSettings` 并入 `MSCore`**：`MSCore` 就不可能"无外部依赖"，§7 的无头测试前提失效。

## 后果与判据
正面：agent 按目录领活；依赖可机检。
负面：模块多 → 改跨模块接口要动多处（缓解：接口先写在 `modules.md`）。
判据：`make check` 里一条 import 静态检查（解析各模块 `import` 与 ADR-012 图比对，发现反向边即失败）；新增模块必须同时改 `charter.md` §4 与 `modules.md`。
