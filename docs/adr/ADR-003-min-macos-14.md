# ADR-003 最低系统版本 macOS 14 Sonoma

状态：**proposed**（= 章程 Q-01，待用户签字） 日期：2026-11-16 相关：ADR-007、ADR-017

## 背景
采集主路径 `SCScreenshotManager.captureImage` 需要 macOS 14.0+（官方 A2，`docs/reference/snipaste-gap.md` §7 已核实）。`SCStream` 从 12.3 起可用，但"起流取一帧"对冻结语义是更重、更慢的路。当前开发机是 macOS 15.7.4 / SDK 26.2。

## 决策（建议）
最低 **macOS 14.0**，`Package.swift` 写 `platforms: [.macOS(.v14)]`，`LSMinimumSystemVersion` 同步。

## 已考虑并否决的方案
| 方案 | 内容 | 否决理由 | 什么证据会翻案 |
|---|---|---|---|
| macOS 13 | 主路径退到 `CGDisplayCreateImage`（已弃用）+ `SCStream` | 要同时维护两套采集、且 13 的屏幕录制权限提示与 14/15 不同；`CGWindowListCreateImage` 在 14 已弃用（A3） | 只有"用户自己仍在 macOS 13"才翻案；否则不做 |
| macOS 15 | 只支持最新 | 收益（API 差异）不足以抵消风险，且我们没有 macOS 15 独占需求 | 若 macOS 14 上出现无法绕开的采集缺陷（如实测 DPI 元数据错误） |
| macOS 12 | — | 屏幕录制权限模型与 SCK 均偏旧 | 不会 |

## 后果
正面：一条采集主路径、一套权限行为、一套兼容矩阵（NFR 兼容表按 14/15/26 三档）。
负面：明确放弃 macOS 13 及以下用户（自用可接受）。
影响范围：**版本选择直接决定 `docs/requirements/nfr.md` 的兼容矩阵行数与 ADR-007 的兜底路径是否存在**。

## 判据
`make doctor` 检查宿主系统 ≥14.0 并在低版本上拒绝构建并给出可读原因；Info.plist `LSMinimumSystemVersion` 与包声明一致（脚本比对，不靠人眼）。

## 受影响
`Packages/MacShotKit/Package.swift`、`Config/Info.plist`、`docs/requirements/nfr.md`、`docs/architecture/capture-pipeline.md` §2。
