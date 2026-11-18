# Git、版本与发布

> 真源：提交粒度、分支、版本号、产物与发布流程。`AGENTS.md` §3.7/§3.8 是它的摘要。

## 1. 仓库纪律
- 单分支 `main` 工作即可（自用项目，无 PR 流程）。需要实验时用 `spike/<主题>` 分支，**不用裸 stash 存长期实验**（当前 `stash@{0}` 是历史半态，处置见 `T-018`）。
- 不提交：`build/`、`*.dmg`、`*.app`、`.idea/`（Q-10 已按推荐落地）、`Tests/Fixtures` 之外的临时截图、`/tmp` 载荷。
- 提交素材默认不入库；确需基线图（`Tests/Fixtures/*.png`）时，在提交信息里说明"人工确认过的渲染基线"。
- `git add` 只允许显式路径；提交前跑 `git status --short` 复核（防带进 `.env`/密钥/大文件）。
- **`git push` 由用户在终端执行**，agent 不 push、不 `--force`、不 `--no-verify`。

## 2. 提交粒度与信息
- 一档活收口即一个提交（波次边界，不是每个文件一个提交）。
- 格式：`<域>: <为什么这样改>（<T-ID>）`，正文 ≤ 2 行 + 判据行。
  ```
  capture: 用两边分别取整消除 1.799x 下的 ±1px 渗色（T-015）

  V-002 实拍：1px 边缘列颜色一致；换算表 24 例全绿
  ```
- 文档改动与代码改动**同批提交**（NFR-036）；纯文档提交用 `docs:` 前缀并写清影响了哪几份真源。
- 禁止：`wip`、`fix`、`update` 这类无信息提交；把他人未收口的改动一起 commit。

## 3. 提交前检查（主线收口时执行）
```sh
make check                       # H 类门禁
git status --short               # 只有预期文件
grep -rn "UNVERIFIED" --include=*.swift . | wc -l   # 未验证项数量，记录进 done.md
sed -n '1,20p' docs/tasks/todo.md                    # 第 0 档是否还红（红 ⇒ 不该有代码提交）
```

## 4. 版本号
`CFBundleShortVersionString` = `MAJOR.MINOR.PATCH`，`CFBundleVersion` = 单调构建号。
- `0.x.y`：M-0…M-5 期间的自用里程碑（当前阶段）。
- `1.0.0`：M-6 出口且 `nfr.md` §5 兼容矩阵无空格（有空格则发布说明缩小支持范围，不硬称支持）。
- 规则：改动 schema（`ADR-009`）⇒ MINOR +1 并写迁移说明；新增 P1 功能 ⇒ MINOR +1；判据回归修复 ⇒ PATCH +1。
- 版本号只在 `Config/Info.plist` + 一个 `BuildInfo` 常量出现（防两处漂移），`make doctor` 打印实际读到的值。

## 5. 产物与发布（ad-hoc，ADR-004）
```sh
make build      # build/MacShot.app（Debug）
make release    # Release 配置 + 优化编译
make dmg        # build/MacShot-<version>.dmg
make sign       # codesign --force -s -  （不 --deep 除非确有必要，理由见 ADR-004 风险）
make install    # 先打 DMG，再从 DMG 里装；覆盖已有安装，且不带 quarantine
```
发布检查表（M-6）：
1. `codesign -dv` 显示 `Signature=adhoc`、无 TeamIdentifier。
2. `spctl -a -vv` 结论按"本机自建、无 quarantine"记录（不要求通过 Gatekeeper 评估）。
3. 全新用户流程：`tccutil reset` → 安装 → 首启 → 引导窗 → 授权 → 截图/贴图/标注/复制四件事都成功（V-021 + V-001…V-005）。
4. **重装后屏幕录制授权是否失效**必须实测并写进 `runbook/permissions-tcc.md`（ad-hoc 签名的已知风险）。
5. 已知限制清单成文：macOS 13 不支持、键盘-only 未闭环（NFR-022）、VoiceOver 不完整范围（V-028）、不能直接发给他人（B-010）。

## 6. 回滚
- 里程碑出口失败 ⇒ `git revert` 整个提交（不 reset 已共享的历史；本仓库只有你，但保持习惯）。
- 判据回退（V-018/V-019 破线）⇒ 不是回滚代码，而是**回到裁决层**：开 Q-12/ADR-019 复审，并在 `blocked.md` 记触发数值。

## 7. 变更日志
`CHANGELOG.md` 从 `0.1.0` 起写，条目按"用户能感知的变化"组织，不按提交组织；每条挂 V-ID 或 FR-ID。裁决层的变更（Q/ADR 转 accepted）记在 `docs/adr/README.md` 的状态列，不重复进 CHANGELOG。
