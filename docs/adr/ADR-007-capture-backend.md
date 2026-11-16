# ADR-007 采集后端：SCScreenshotManager 主路 + CoreGraphics 兜底

状态：**accepted**（用户 2026-11-16 签字；同批签 ADR-003 与 ADR-008） 相关：ADR-003、ADR-008、FR-CAP-001/004/005

> 裁决记录：用户的原话是"采集的时候冻结快照，暂时不需要考虑实时"。那句话命中的是 **ADR-008（冻结语义）**，
> 本条是它的下游结论——不做实时流 ⇒ 不需要 `SCStream` 起流 ⇒ 主路径就是单帧 API。两者同批 accepted。
> **仍未定的一小格**：兜底路径（`CGDisplayCreateImage`）要不要保留。当前定案是"保留但只在启动时决定一次"；
> 若你希望 P0 完全不写兜底代码（少一条永不执行的分支、少一份弃用警告），说一声我改成"主路失败即报错引导"。

## 背景
需要"一次一帧、整屏、含正确 scale、低延迟"的抓取。已核实：`SCScreenshotManager.captureImage` macOS 14.0+（A2）；`SCStream` 12.3+（A1）；`CGWindowListCreateImage` 在 14.0 弃用（A3）；`CGDisplayCreateImage` 官方标 deprecated 但**具体版本未确认**（A4，疑 15.0，待实测）。

## 决策
1. 主路：`SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: nil) 的显示器过滤器, configuration:)`，`configuration.width/height = round(logical × scale)`，`showCursor = false`，`pixelFormat = kCVPixelFormatType_32BGRA`。
2. 兜底：`CGDisplayCreateImage`（只在主路初始化失败时启用一次，记日志 `capture.backend=cg-legacy`，不做逐次回退）。
3. 窗口/元素干净截图（P1 `FR-CAP-011`）用 `SCContentFilter(desktopIndependentWindow:)`，与主路同一框架，不引第二套采集。
4. 后端选择在**进程启动时决定一次**，会话内不切换。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案 |
|---|---|---|
| `SCStream` 起流取首帧 | 起流+会话建立的固定成本落在"按下热键"这一最敏感时刻；一帧就走用不上流 | 实测若 `SCScreenshotManager` 单次调用延迟 > 起流方案（不太可能），换 |
| `CGWindowListCreateImage`（含桌面/不含桌面可控） | 14.0 已弃用（A3），且返回内容随系统策略变化（第三方窗口排除） | 不会 |
| 实时屏幕流常驻（预览式截图） | 内存/功耗与"只在截图时抓一帧"的目标相反 | 不会 |
| 逐次自动回退（SCK 失败即 CG） | 会掩盖权限问题，出现"有时能截有时全黑"最难查的状态 | 不会（保留"启动时决定一次"） |

## 后果
正面：与 ADR-003（macOS 14）互相成就，一条路径、权限提示一致。
负面：放弃 macOS 13（若 Q-01 选 13，本 ADR 主路不成立，须整体重写）。
风险：SCK 在某些外接显示器/投影模式下返回尺寸异常 —— M-1 必须实测双屏 + 非整数缩放。

## 判据
1. `V-001`：日志出现 `capture.backend=sck`；同机重启后一致。
2. `FR-CAP-004`：像素正确性表在 scale ∈ {1, 2, 1.799} 全绿。
3. `t.hotkey→frozen` 目标值实测（`capture-pipeline.md` §7）并记入 `done.md`。

## 受影响
`MSCapture` 实现、`docs/requirements/nfr.md` 兼容矩阵、`docs/runbook/permissions-tcc.md`。
