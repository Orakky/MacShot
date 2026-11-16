# AGENTS.md — MacShot

macOS 原生截图 → 标注 → 贴图置顶 → 剪贴板 工具（形态参考 Snipaste）。Swift + AppKit，Xcode 工程 + 本地 SPM 多模块包。

## 0. 当前阶段：M-0 已落地，裁决与实现并行（先读这条）

用户 2026-11-16 放行开发：**未签决策按 `docs/charter.md` §6 顶部的临时默认档实现**，不再是"没签就不能写"。现状：

- 已裁决：D-01 首版只做四大件 / D-02 本机 ad-hoc 签名 / D-03 Xcode + SPM / D-04 贴图携带可编辑标注层（见 `docs/charter.md` §1）。
- 未裁决：`docs/charter.md` §6 的 Q-01…Q-15，与 `docs/adr/README.md` 中状态为 `proposed` 的行。
- 正式代码在 `App/` + `Packages/MacShotKit/` + `MacShot.xcodeproj`（10 模块 + 47 条单测）。`stash@{0}` 那份旧骨架已 `apply` 并按 accepted ADR 改写完毕（`modules.md` §12 的 3 处不符都处理了），**不要再 pop 第二次**。

改任何被临时默认档覆盖的行为前，先看 §6 表并问用户；改了就去更新那张表（文档与代码同批提交，NFR-036）。

## 1. 上岗顺序

`docs/charter.md` → `docs/requirements/requirements.md` → `docs/plan/roadmap.md`（取当前 M）→ `docs/tasks/todo.md`（取一个 T）→ 按需读 `docs/architecture/<模块>.md` 与 `docs/design/screens.md`。

## 2. 命令（已生效，与 `docs/runbook/build-and-verify.md` 一致）

```sh
make doctor            # 环境自检：Xcode / SDK / 证书 / 构建号 / 权限 / 未验证项计数
make build             # xcodebuild 无头构建 .app
make test              # swift test（Packages/MacShotKit，无需 Xcode GUI）
make run               # 构建并启动（开发用；先杀旧进程）
make release           # Release 配置构建
make dmg               # 产出 build/MacShot-<version>.dmg（ad-hoc 签名）
make install           # 装到 /Applications 或 ~/Applications（去 quarantine）
make check             # 本地门禁：build + test + 风格/依赖方向/文档一致性
make clean             # 清 build 与 Derived
make probe             # 采一帧并打印尺寸/耗时/权限（V-001/V-019 取证）
scripts/reset-tcc.sh   # 重置屏幕录制授权（排查黑图）
```

## 3. 纪律（违反 = 返工）

1. **未观察不写完成。** 说"做完了"必须附判据：命令输出 / 日志行 / 读数 / 截图路径。写不出判据就写"未验证 + 原因"。
2. **一个事实只有一个家。** 需求进 `requirements.md`、决策进 `adr/`、屏幕规格进 `design/screens.md`、待办进 `tasks/todo.md`。别处只写 `见 X#ID`。
3. **`proposed` 的 ADR 不落地为代码**；要动就先补 ADR 并请用户签字。
4. **不改 `MacShot.xcodeproj/project.pbxproj`。** 工程用同步文件夹组，新增源文件放进 `App/` 或 `Packages/MacShotKit/Sources/<Module>/` 即被自动纳管。
5. **模块依赖方向不许反**（`docs/charter.md` §4）。逻辑代码写在包里、能被 `swift test` 覆盖；`App/` 只做组合根与全局装配。
6. **坐标系不许"顺手换算"**（ADR-013）。跨空间换算必须调用显式函数；新换算先写单测。
7. 只用显式路径 `git add <路径>`；提交前 `git status` 复核。`git push` 由用户在终端执行。
8. 交付产物（`build/`、DMG、截图素材、`.idea/`）默认不入库。
9. 遇到与文档矛盾的实现约束 → 记进 `docs/tasks/blocked.md` 并问用户，不自行改设计。
10. 不引入第三方依赖，除非 ADR-015 被 accepted 且写明来源（本机当前**没有 brew**）。
11. **分发器不许 `default:` 空转**（effect/command/intent 的 switch 必须穷举）。2026-11-16 的遮罩卡死事故就是 `default: break` 吞掉了 `closeOverlay`；`check-style.sh` 已拦。全屏模态必须有 ≥2 条退出路径。

## 4. 领活与并行

- 一档活 = 一个 `T-0xx`，范围以"文件域 + 判据"界定；跨档不改同一文件。
- 并行开发按模块目录切；`Package.swift`、`AGENTS.md`、`charter.md`、`docs/README.md` **只允许主线改**。
- 做完一档：更新该 T 行（→ `done.md` 附证据）→ 跑 `make check` → 提交（信息式摘要，1–2 句"为什么"）。
- 半态（写到一半需要换方向）：`git stash push -u -m "<T-0xx> 半态" -- <显式路径>` 收起，回来先 `git stash list` 认领，不要 `pop` 别人的。

## 5. 禁止新增的东西

无归属大件的 P0 需求（§D-01）、独立"快速编辑器"窗口（D-04 已把再编辑放进贴图窗）、云端/账号/录屏/滚动截图（`requirements.md` §5 明确不做）、只在 `App/` 外的全局单例、未版本化的文档 schema。

## 6. 文档写作约定

- 中文正文、ASCII 文件名与代码标识符；表格优先于长段。
- 每份文档开头一行说明"本文是真源 / 只是引用"。
- ID 前缀规则见 `docs/charter.md` §5。新增文档必须登记到 `docs/README.md` §2 并标状态。
- 状态词只用：`待写` / `草稿` / `待裁决` / `accepted` / `dropped` / `superseded`。
