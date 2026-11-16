# ADR-015 零第三方依赖 + 本机门禁脚本（无 brew 环境）

状态：**proposed** 日期：2026-11-16 相关：ADR-001、ADR-010、`docs/protocol/coding-conventions.md`

## 背景
本机没有 homebrew、没有签名证书（ADR-004）。引入任何第三方工具链（xcodegen/tuist/swiftlint/swiftformat/MASShortcut）都意味着"要么装工具、要么手写构建脚本"，而工具来源与更新无人可审。

## 决策（建议）
1. **P0 零第三方依赖**：只用 Apple 框架（AppKit/CoreGraphics/ScreenCaptureKit/Carbon/ImageIO/os.log）。
2. 规范检查用**自家脚本**代替 lint 工具：`scripts/check-style.sh`（正则级门禁：禁 `try!`、禁裸 `print`、禁 `CGFloat` 表示像素、禁模块反向 import、禁散落热键魔数），在 `make check` 里跑。
3. 若将来必须引入工具，须：写明来源与版本、可离线校验（`shasum`）、且**不进入 app 产物**（只进开发链路），并开新 ADR 取代本条。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案 |
|---|---|---|
| SwiftLint / SwiftFormat | 收益（风格一致性）可由 40 行正则脚本覆盖 80%；代价是安装 + 规则学习 + 团队（=你一个人）反复调规则 | 若 `check-style.sh` 出现"漏检导致的同类 bug ≥3 次"，即引 SwiftLint 并写明安装路径 |
| XcodeGen / Tuist | 同步文件夹组已解决 pbxproj 手改问题（ADR-001） | ADR-001 的翻案条件成立时一起翻 |
| 第三方快捷键/图标/图片库 | 见 ADR-010；图标走 SF Symbols | 不会 |
| 引入 SPM 远程依赖（哪怕纯 Swift） | 无法在本机验证来源、离线不可构建 | 若出现自写成本 >2 人日的通用能力（如 JSON Schema 校验），逐项开 ADR |

## 后果
正面：离线可构建、可复现、无供应链面；agent 不需要网络就能 `make check`。
负面：静态检查能力弱于真 lint；"文件行数上限"这类规则要靠脚本自觉（可接受）。
连带义务：`make doctor` 输出 Xcode/SDK/Swift 版本，任何构建问题先跑它。

## 判据
`make check` 在无网络（`networksetup -setairportpower` 关闭）下仍能跑通全部门禁 —— 这条本身是 ADR-015 的存在理由，M-0 实测一次即可归档。
