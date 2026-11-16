# Runbook：屏幕录制权限（TCC）与排查

> 事实基线：截图需要 **屏幕录制** 权限，自 macOS 10.15 Catalina 起强制（Snipaste 官方故障排查同结论，`docs/reference/snipaste-gap.md` §6）。首版**不需要**辅助功能权限（那是 P1 的元素检测/像素光标才需要，`hotkey-and-permissions.md` §4）。

## 1. 症状 → 结论对照

| 症状 | 结论 | 下一步 |
|---|---|---|
| 截图/遮罩里全是黑或只有壁纸 | 未授权 | §2 |
| 能截到桌面但截不到某些窗口（浏览器/DRM 内容） | 系统对特定内容的保护，不是我们的 bug | 记入 `troubleshooting.md`，不改动采集逻辑 |
| 昨天能用今天全黑 | 授权随签名/路径变化失效（ad-hoc 风险） | §3 |
| 授权列表里没有 MacShot | 从未成功触发过权限请求 | §2 步骤 1 |
| 授权后仍黑 | 未重启进程（大概率） | §2 步骤 4 |

## 2. 首次授权流程（判据 = V-021）

1. 触发一次采集（`F1` 或 `make run` 后的引导窗）→ 系统应弹"MacShot 想录制此屏幕"；不弹就去步骤 2。
2. `打开系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制`（各版本面板名不同，**待实测**确认 macOS 14/15/26 的准确标题，回填 `UI-007` 文案）。
3. 勾选 MacShot。列表中没有该 app 时：先让 app 触发过一次采集；仍没有则 `tccutil reset ScreenCapture com.macshot.app` 后重启 app。
4. **重启 MacShot 进程**（`make run` 会先杀旧进程）。授权变更对已运行进程通常不生效——这条的具体表现要在 M-1 实测确认（B-005）。
5. 验证：`F1` 后遮罩内能看到真实桌面内容；日志 `capture.perm=granted`。

程序内探测：`CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`，可用最低版本 **待实测**（不预设 macOS 14 一定有）；不可用时退化为"抓一帧 + 黑图启发式"（`capture-pipeline.md` §6）。

## 2b. 实测结论（2026-11-16，MacShot 0.1.0 / macOS 15.7.4）

**ad-hoc 签名的 app 会被屏幕录制直接预拒绝，且不弹授权框。** 三条实测证据：

| 试法 | 结果 |
|---|---|
| 终端直接跑二进制 `…/MacShot --probe-capture` | `granted`，能截图 —— 但那是**继承 Terminal 的授权**，不代表 app 自己有权 |
| `open MacShot.app --args --snip-now`（DerivedData 路径） | `preflight=denied` → SCK 抛 `SCStreamErrorDomain -3801`，**35ms 返回，无系统弹窗** |
| `make install` 后从 `~/Applications` 跑 | 同样 `-3801` 预拒绝 |
| `tccutil reset ScreenCapture com.macshot.app` 后再试 | 仍 `-3801` |

因此曾经的"preflight 未授权就放弃采集"是**双重错误**：既拿不到授权，又让 app 永远进不了系统列表。现在改成：无论如何先真试一次采集，失败再引导。

### 三条出路（按代价排序）

| 方案 | 做法 | 代价 | 状态 |
|---|---|---|---|
| B. 手动勾选 | 系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制，看列表里有没有 MacShot，有就勾上 → 重启 app | 零改动，但重装/重签后可能要重勾 | **先试这个** |
| A. 本地自签证书 | 钥匙串建一个 Code Signing 自签身份，`codesign -s "MacShot Dev"`，让 TCC 身份跨构建稳定 | 需要 sudo 改系统信任；只解决"稳定"，不保证 adhoc 之外的预拒绝消失 → **必须先小样验证** | 待验证（B-015/T-104） |
| C. 开发者证书 | Developer ID 签名 | 99 美元/年 + 外网 | 目前无账号 |
| D. 开发期兜底 | 终端直接跑二进制，借 Terminal 已授予的屏幕录制 | 不能日常用，日志混在终端 | 仅用于取证 |

## 3. ad-hoc 签名的坑（ADR-004 风险条 → 已升级为阻塞项）

TCC 的屏幕录制记录按 **bundle 身份 + 签名** 判定。ad-hoc 签名每次重签都可能变身份 ⇒ 表现就是"每次重装都要重新授权"。

排查与缓解：
```sh
codesign -dv build/MacShot.app 2>&1 | grep -E 'Signature|Identifier|CDHash'
codesign -dvvv build/MacShot.app 2>&1 | grep TeamIdentifier      # 期望为空
xattr -l /Applications/MacShot.app                                # 期望无 com.apple.quarantine
```
- 缓解 1：`make sign` 只在版本号变化时重签，日常 `make build` 不 `--force --deep`（脚本已按此写，`build-and-verify.md` §1）。
- 缓解 2：固定安装路径与 bundle id，不要今天跑 `build/` 明天跑 `~/Downloads/` —— 不同路径也会被当成不同对象。
- 缓解 3：若实测确认"每次重装都要重新授权"，把它写进发布说明与 `troubleshooting.md`，并在引导窗文案里提前说（用户预期管理比技术绕法便宜）。
- 根治：需要 Developer ID 证书（B-010，需外部条件，届时补 ADR）。

## 4. 复位与清理

```sh
scripts/reset-tcc.sh            # = tccutil reset ScreenCapture com.macshot.app
log stream --predicate 'subsystem == "com.macshot.app"' --info   # 看自己的日志
log show --predicate 'subsystem == "com.apple.tccd"' --last 5m   # 看系统授权判定
```

## 5. 实测记录（追加，不删除）

| 日期 | 系统 | 操作 | 观察到的结果 |
|---|---|---|---|
| 2026-11-16 | macOS 15.7.4 | 未执行（无 app） | 面板标题文案、重启必要性、重装是否失效授权 —— 三条全部待实测（B-005） |
