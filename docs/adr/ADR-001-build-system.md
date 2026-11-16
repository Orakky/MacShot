# ADR-001 构建体系：Xcode 工程（同步文件夹组）+ 本地 SPM 多模块包

状态：**accepted**（D-03，用户 2026-11-16 确认） 相关：ADR-012、ADR-015

## 背景
需要同时满足：① 人能在 Xcode 里跑/调试/看窗口；② agent 能在纯 CLI 下构建与跑单测；③ 工程文件是文本、可 diff、多人并行不冲突；④ 本机没有 homebrew，不能依赖 xcodegen/tuist。

## 决策
- 仓库根放 `MacShot.xcodeproj`，app target 用 **`PBXFileSystemSynchronizedRootGroup`**（Xcode 16+）指向 `App/`：新增/删除源文件由文件系统决定，**`project.pbxproj` 不再需要手改**。
- 逻辑代码放本地包 `Packages/MacShotKit/`（10 模块），app target 通过 `XCLocalSwiftPackageReference` 引用；单测在包内，`swift test` 可无头跑。
- `Config/Info.plist` 与 entitlements 放在同步组之外（`Config/`），避免被当资源复制。
- `Makefile` + `scripts/` 提供 `doctor/build/test/run/dmg/check`。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案（决策门） |
|---|---|---|
| 纯 SPM + 脚本手工拼 `.app` | 不能在 Xcode 里断点/预览，asset catalog 与权限调试要自己造轮子 | 若 `xcodebuild` 在无 GUI/CI 环境无法稳定产出可运行 .app（实测失败 2 次以上且无解），退回此方案 |
| XcodeGen | 本机无 brew，需引入第三方二进制；且同步文件夹组已消除 pbxproj 手改痛点 | 若同步文件夹组出现"资源/排除规则"无法满足的需求（例如需要按配置排除文件） |
| Tuist | 依赖更重、需网络与账号体系 | 同上，且项目规模远超当前 |
| 手写完整 pbxproj（不用同步组） | agent 每次加文件都要改工程文件 → 并行必冲突 | 不会翻案 |

## 后果
正面：agent 加文件零工程文件改动；单测不需要 Xcode；`git diff` 干净。
负面：pbxproj 仍需一次正确手写（M-0 的准出项）；同步组的隐式纳管要求目录纪律（不能把大文件随便丢进 `App/`）。
风险：Xcode 版本升级改变同步组语义 → `make doctor` 记录 Xcode 版本，升级前跑一轮门禁。

## 判据
`xcodebuild -project MacShot.xcodeproj -scheme MacShot -configuration Debug build` 无头成功；在 `App/` 新增一个 `.swift` 后**不改任何工程文件**再次构建即包含该文件；`cd Packages/MacShotKit && swift test` 通过。

## 受影响
`Makefile`、`scripts/*`、`docs/runbook/build-and-verify.md`、`AGENTS.md` §2/§3.4。
