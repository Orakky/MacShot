# ADR-009 标注文档编码：带 schemaVersion 的 JSON，M-1 出口冻结

状态：**proposed** 日期：2026-11-16 相关：ADR-005、FR-SET-003、Q-06

## 背景
D-04 让 `AnnotationDocument` 成为正式产物。P0 不落盘（Q-06 推荐 A），但**结构必须在 M-1 冻结**，因为贴图、导出、设置默认样式三处都引用它；P1 的 `.macshot` 只是"同一 JSON + 位图"的容器化。

## 决策（建议）
1. 编码：**JSON**，字段名稳定（不依赖 Swift 属性名的自动编码细节，显式 `CodingKeys`），`elements` 按 `(zIndex, id)` 稳定排序。
2. 顶层 `schemaVersion: Int`（当前 1）；`Kind`/`DashPattern` 等用稳定字符串 rawValue，**新增只加值、旧值永不改义**。
3. 几何一律整数像素；颜色 `[r,g,b,a]`（a 为 0–1 的 Double）；不写色名、不写设备相关值。
4. 读到 `schemaVersion > 当前支持` ⇒ 拒绝并提示（不做向前猜解）；读到更低版本 ⇒ 走显式迁移器（P1 才有第 2 版）。
5. `.macshot`（P1）= 目录包：`document.json` + `source.png`；或单文件 JSON 内嵌 base64 —— 二者**不同时支持**，届时选包格式。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案 |
|---|---|---|
| Protobuf / Swift-Codable 二进制 | 不可读、不可 diff、出问题只能靠工具链看；首版元素结构简单 | 若文档大小/解析时间成为瓶颈（实测 > 10MB 或 > 50ms/张） |
| XML / plist | 冗长，人工写测试夹具痛苦 | 不会 |
| 把标注烘焙进 PNG 元数据（tEXt） | 一份数据两处真相（像素与矢量），与"单向烘焙"冲突 | 不会 |
| 不版本化（等需要时再说） | 恰恰是 D-04 的代价来源：改了 schema 就丢用户的贴图 | 不会 |

## 后果
正面：测试夹具是人能写的 JSON；跨版本可读性有保障；`--deep` 排查时能直接看文档。
负面：JSON 对浮点/大数组的确定性要求要自己守（写死"整数坐标"这一条就是为此）。
连带义务：设置项 `AppPreferences` 同用 `schemaVersion` 风格（FR-SET-003），两处规则一致，不各造一套。

## 判据
1. `encode → decode → encode` 字节稳定（单测）。
2. 未知 `kind` / 未知高版本 的拒绝路径有用例。
3. M-1 出口时 `git log` 里 schema 字段集合不再变化（此后只能加，不能改语义）。

## 受影响
`MSAnnotate`、`MSSettings`、`docs/architecture/annotate-model.md` §2、P1 的 `FR-EXP-012`。
