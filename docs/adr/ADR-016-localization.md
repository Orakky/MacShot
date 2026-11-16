# ADR-016 本地化：中英常量表，暂不引入 String Catalog

状态：**proposed** 日期：2026-11-16 相关：FR-SET-013、`coding-conventions.md` §9

## 背景
你是中文用户，界面需要中英文双语；首版只做中文也能用，但截图工具的错误/权限文案一旦看不懂就变成"无法自助排查"。String Catalog（`.xcstrings`）是 JSON，agent 可改，但它把文案绑在 app target 的构建链路里，而我们的文案大量来自**包内模块**（`MSAnnotate` 的样式名、`MSError` 的 `userTextKey`）。

## 决策（建议）
1. 首版界面语言：**跟随系统**（`AppleLanguages`），中文环境出中文，否则英文。
2. 文案源：`MSCore/MSStrings.swift` 一张 key → (zh, en) 常量表 + `MSString.key(_:)` 取值；`MSError` 只带 key，不带成品句子。
3. 命名：`ui.<屏>.<元素>`（如 `ui.overlay.warn.clearAnnotations`）、`err.<域>.<原因>`、`menu.<项>`。
4. 表是**唯一真源**，`docs/design/screens.md` 里出现的中文串必须能在表里找到同名 key（脚本可校验，`T-0xx`）。
5. 若后续要上架/多语言，再迁 String Catalog，key 命名不变即可平移（迁移动作开新 ADR）。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案 |
|---|---|---|
| `.strings`/`.lproj` 文件 | 二进制构建产物依赖、agent 改起来易出转义问题（尤其中文 + `%@`） | 不会 |
| String Catalog 现在就用 | 包内模块拿不到 app target 的 catalog，得做资源包 + `Bundle.module`，为 2 种语言不划算 | 一旦需要第 3 种语言，或要上架，立即翻案 |
| 只做中文 | 权限/错误文案在英文系统下会中英混杂（系统控件英文、我们中文），排查时反而更难对齐 | 不会 |

## 后果
负面：无复数/性别形式（中文不需要；英文的 "1 image / 2 images" 需自己写格式化助手）；无翻译平台可挂。
连带义务：所有中文文案不硬编码在 view 里（`check-style.sh` 门禁：中文字符只允许出现在 `MSStrings.swift`，例外要注释说明）。

## 判据
`grep -RnP '[\x{4e00}-\x{9fff}]' App Packages/MacShotKit/Sources --include=*.swift` 的命中只出现在 `MSStrings.swift` 与测试夹具中；切系统语言后重启 app，全部界面文案随之切换（实拍）。
