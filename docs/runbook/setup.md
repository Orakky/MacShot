# Runbook：环境搭建（本机实测路径）

> 事实基线取自 2026-11-16 本机：`sw_vers` → macOS 15.7.4 (24G517) / arm64；`xcodebuild -version` → Xcode 26.3 (17C529)；`swift --version` → Swift 6.2.4，target `arm64-apple-macosx15.0`；`xcrun --sdk macosx --show-sdk-version` → 26.2；`/opt/homebrew/bin/brew` **不存在**；`security find-identity -v -p codesigning` → **0 valid identities**。
> 换机器时先跑 `make doctor`（M-0 后）并把输出贴进本文件末尾的"实测记录"。

## 1. 需要装的东西：**只有 Xcode**

```sh
# 确认工具链（已满足则跳过）
xcode-select -p            # 期望 /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
```
- **不需要** brew / xcodegen / tuist / swiftlint / 任何包管理器（ADR-001、ADR-015）。
- **不需要** Apple Developer 账号（ADR-004；要走分发时再看 B-010）。
- 需要一次性同意许可：`sudo xcodebuild -license accept`（若首次运行提示）。
- 需要一次本地签名身份准备：无证书时用 ad-hoc（`codesign -s -`），无需钥匙串配置。

## 2. 取代码与首次构建

```sh
git clone <你的仓库> MacShot && cd MacShot
git checkout main
open MacShot.xcodeproj          # 首次打开：Xcode 会解析本地 SPM 包（离线可用，无远程依赖）
```
CLI 路线（agent 用）：
```sh
make doctor      # 打印 Xcode/SDK/Swift/证书/系统版本 + 权限状态
make build       # xcodebuild 无头 → build/MacShot.app
make test        # cd Packages/MacShotKit && swift test
make run         # 构建并启动（菜单栏出现图标即成功）
```
> M-0 之前这些目标**不存在**（当前仓库只有文档）。`AGENTS.md` §2 已注明"待 M-0 落地生效"。

## 3. 权限（一次性，最容易踩）

见 `docs/runbook/permissions-tcc.md`。要点：首版只需要 **屏幕录制** 一项（`docs/architecture/hotkey-and-permissions.md` §4）；授权后通常需要重启进程（**待实测**，B-005）。

## 4. 日常开发循环

```sh
make check        # 门禁：build + swift test + 风格/依赖方向/文档一致性（verification.md 的 H 类）
make run          # 改完跑一次，实拍判据（P 类）从这里开始
make dmg          # 里程碑出口产物
scripts/reset-tcc.sh   # 黑图/权限诡异时的第一招
```

## 5. 换机器 / 新 agent 接手的最小清单

1. `sed -n '1,40p' docs/README.md`（当前阶段）→ 若第 0 档仍红，**只读不写代码**。
2. `git status --short`；`git stash list`（有 `architecture-spike` = 半态，别 pop）。
3. `make doctor` 输出对照 §1 的基线，任何不一致先写进 `docs/tasks/blocked.md`。
4. `docs/tasks/todo.md` 取一档活，按 `docs/templates/task-card.md` 填六项再开工。

## 6. 实测记录（本文件唯一的动态段落，追加不删除）

| 日期 | 机器 | `make doctor` 关键行 | 结论 |
|---|---|---|---|
| 2026-11-16 | MacBook (arm64, macOS 15.7.4, Xcode 26.3) | 尚无脚本；手工核实见 §1 顶部 | 文档裁决期，未开始构建 |
