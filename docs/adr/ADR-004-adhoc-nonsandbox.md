# ADR-004 交付形态：非沙盒 + ad-hoc 签名 + 本机直装

状态：**accepted**（D-02，用户 2026-11-16 确认） 相关：ADR-001、FR-EXP-003、`docs/runbook/`

## 背景
本机 `security find-identity -v -p codesigning` = **0 个有效身份**，没有 Apple Developer 证书，也没有 brew 可以装公证工具链。首版目标是"自己天天用"，不是分发给别人。

## 决策
- **不启用 App Sandbox**（`com.security.app-sandbox = false`），entitlements 只留必要项（无网络、无 jit）。
- 产物：`build/MacShot.app` + `build/MacShot.dmg`，`codesign --force --deep -s -`（ad-hoc）。
- 装到本机：`make install` 先打 DMG 再从 DMG 里 `ditto` 到 `/Applications`（或 `~/Applications`），不带 quarantine 属性 → Gatekeeper 不拦。
- 全局热键、跨 Space 贴图、任意目录导出、`tccutil` 排查脚本，都按"非沙盒"写判据。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据/条件会翻案（决策门） |
|---|---|---|
| Developer ID 签名 + `notarytool` 公证 | 当前无证书、无凭据，写完也无法验证；不是技术问题而是账号问题 | **一旦出现"要给第二个人用"的需求即翻案**：需补 ADR（99 美元/年 + 证书 + API key），代码不变，只改 `Config/*.entitlements` 与打包脚本 |
| Mac App Store（沙盒） | 沙盒与四大件冲突：全局热键与跨 Space 贴图的体验受限、导出目录受安全书签约束、`tccutil` 类排查不可用；对截图工具是净损失 | 不会（除非目标变成"上架"本身） |
| 自建根证书 + 本地信任 | 换机器就失效，且把排查复杂度转嫁给未来的自己 | 不会 |
| 完全不分发（只从 Xcode 跑 DerivedData） | 连 DMG 都不出，日常使用与备份都不方便 | 不会 |

## 后果
正面：首版可实跑、可验证；所有 Snipaste 式能力都不被沙盒砍。
负面：**不能直接发给别人**（下载后会被 Gatekeeper 拦，需右键打开或 `xattr -d com.apple.quarantine`）；ad-hoc 签名每次重建签名变化，TCC"屏幕录制"授权是按 bundle 身份记的 → **重新 ad-hoc 签名后可能需要重新授权**（这是真实使用坑，已写进 `docs/runbook/permissions-tcc.md`，M-1 必须实测确认其表现）。
风险：签名不稳定导致授权反复失效，会直接影响"快速截图"的可信度。缓解：M-0 起固定 bundle id 与可执行文件路径，签名只覆盖一次，避免每次 build 都 `--force --deep`。

## 判据
1. `codesign -dv build/MacShot.app` 显示 `Signature=adhoc` 且无 TeamIdentifier。
2. `spctl -a -vv` 的结论按"本机自建、无 quarantine"预期记录（不要求通过 Gatekeeper 评估）。
3. 重装后首次启动，屏幕录制授权流程能走通（`V-002`）。

## 受影响
`Config/MacShot.entitlements`、`Makefile`（`sign`/`install` 目标）、`docs/runbook/permissions-tcc.md`、NFR 兼容与隐私类。
