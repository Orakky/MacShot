# Runbook：问题库（持续累积）

> 规则：**每个真实遇到过的坑进一条**，格式固定为「症状 / 根因 / 处理 / 预防（文档或门禁改了哪里）」。**不许只留"重启试试"**——根因没查清就进 `docs/tasks/blocked.md` 挂 `需实测`。
> 本文件现在只有"预期会发生但尚未发生"的条目；M-1 起按实际遇到的追加（E-xxx 证据里引用条目号）。

## 0. 索引

| ID | 症状 | 状态 |
|---|---|---|
| P-001 | 截图全黑 / 只有壁纸 | 预期，未遇 |
| P-002 | 重装后需要重新授权 / 每次启动都问权限 | **实测确认**（ad-hoc 无 DR，TCC 按 cdhash 记账）→ Q-18 |
| P-003 | 遮罩出现时背景仍在动 | 不应发生（ADR-008 语义），出现即 bug |
| P-004 | 选区边缘多/少 1px | 预期（非整数缩放），已由 ADR-013 §3 步针对 |
| P-005 | 热键 `F1` 变成亮度键 | 预期（MacBook 功能键），未实测 |
| P-006 | 热键被别的 app 占用后无声失效 | 预期（OSStatus 未知，B-004） |
| P-007 | 贴图不显示在全屏 App 之上 | 预期风险（level 未定，B-003） |
| P-008 | 遮罩收不到键盘（app 未激活） | 预期风险（B-002，M-2 头号实验） |
| P-009 | 粘贴到某 app 尺寸翻番 | 预期（DPI 元数据，V-005 针对） |
| P-010 | 粘贴结果与屏上不一致（颜色/标注） | 不应发生，出现即 V-013/V-015 回归失败 |
| P-011 | 剪贴板写入被抢（`changeCount` 变化） | 预期，处理见 `overview.md` §6 |
| P-012 | 拔屏后会话崩溃 | 不应发生（FR-SESS-004 / V-011） |
| P-013 | 贴图内存超预期（NFR-005 破线） | 预期风险，触发回 Q-12 复审 D-04 |
| P-014 | 免面板直存目录不可写 | 预期（卷被卸载），回落保存面板 |
| P-015 | `.macshot`/未来历史文件版本不认识 | 拒绝并提示（ADR-009 / NFR-018），不猜解 |

## 1. 条目正文（示例格式，M-1 起追加真实根因）

### P-005 热键 `F1` 变成亮度键
- 症状：按 `F1` 只调亮度，MacShot 无反应。
- 根因：MacBook 默认把功能键当媒体键；Snipaste 用户社区普遍用 `fn+F1`（第三方来源，官方文档未提，`docs/reference/snipaste-gap.md` §1）。
- 处理：三选一 —— 按 `fn+F1`；系统设置 → 键盘 → "将 F1、F2 等键用作标准功能键"；在设置窗把截图键改成 `⌥⌘A` 类组合。
- 预防：设置窗热键项固定显示这段提示（`screens.md#UI-005` 的 ⓘ 行），首启文案也带上。

### P-001a 一直提示要录屏权限、且系统不弹框（**当前阻塞项**）
- 症状：`F1` 后只有提示，截不到图；系统设置里可能根本没有 MacShot 条目。
- 根因：ad-hoc 签名的 app 被屏幕录制预拒绝（`SCStreamErrorDomain -3801`，35ms 返回，不弹框）。见 `permissions-tcc.md` §2b。
- 处理：① 系统设置里若已有 MacShot → 勾选并重启 app；② 若没有/勾不上 → 走方案 A（本地自签证书）或 C（Developer ID）。
- 预防：`startSnip()` 不再因 preflight 早退；引导窗加了「清除旧授权记录」（`tccutil reset`）。

### P-002 重装后需要重新授权 / 每次启动都问权限（**实测确认**）
- 症状：每次 `make install` 之后，屏幕录制要重勾；且 app 一启动就弹系统权限框。
- 根因（三条，前两条实测过）：
  1. **签名身份每次构建都在变——连"不改代码"都救不了。** `codesign -d -r-` 实测：
     - ad-hoc 签名 `Signature=adhoc`、`TeamIdentifier=not set`，可用来匹配的**只有一串 cdhash**：`designated => cdhash H"a92824b480…"`。
     - **对照实验（2026-11-16，源码一字未改，只 `make clean && make build`）**：二进制 sha256 `5f074f41…` → `fdc887c9…`，cdhash `0f85ca84…` → `ec5d7ed3…`。
     ⇒ 每次重编都是"另一个 app"：旧授权对它无效（采集 `-3801`），且因为新身份从没被决议过，申请权限会**再弹一次系统框**。这就是"每次启动都要问权限"的全部机制。
  2. **我在拒绝路径上每次都申请。** `MSSessionCoordinator` 原来一遇 `-3801` 就调 `CGRequestScreenCaptureAccess()`，于是每按一次 `F1`、每次启动自动截图都可能再敲一次门。已改为**每个进程生命周期只申请一次**（`requestPermissionOnce()` + 注入式 `permissionRequester`，`E-038`）。
  3. 旁因：多份副本 = 多个身份。`~/Applications/MacShot.app`、`build/Derived/…/MacShot.app`、终端里裸跑的二进制是不同路径 + 不同 cdhash，列表里会堆出好几个 MacShot，你以为批过的那个不是当前这个。
- 处理：按 `permissions-tcc.md` §2 重授权（勾完必须重启 app 才生效）；治本走章程 **Q-18** 方案 A（本地自签证书，身份跨构建稳定）。
- 预防：`make doctor` 打印 `CDHash`/`Signature=adhoc` 便于对比；**答复 Q-18 之前不再随手 `make install`**（B-023）。

### P-008 遮罩收不到键盘
- 症状：`F1` 后遮罩出现，`Esc` 与 `Enter` 全无反应；界面上也找不到任何可点的退出入口 → 只能杀进程。
- 根因（实测结论，不是候选）：① `MSOverlayView` 从来不是 first responder（`acceptsFirstResponder` 默认 false，borderless 窗不自动选人）→ `keyDown` 根本没被调用；② `present()` 只抢一次 key，而 `NSApp.activate` 是异步的，实测第 0 次 `key=false`。
- 处理：responder 覆写 + 30…500ms 递进重试抢 key（每次记日志）+ 本地键监视器 + 全局 `Esc` 观察器；再加**三条纯鼠标出路**（左上 ✕、右键任意处、再按截图键）。
- 预防：`OverlayChromeTests` 4 条锁命中区；`V-006` 以 `claimKey#N key=true` 为通过条件；规范 §4b 要求全屏模态必须有 ≥2 条退出路径；`teardown()` 必须摘监视器。

## 2. 追加条目模板

```md
### P-0xx <症状一句话>
- 症状：（用户看到什么 + 日志行）
- 根因：（查到的机制；未查到就写"未定位，见 blocked.md#B-0xx"）
- 处理：（当下怎么绕过）
- 预防：（改了哪份文档/token/门禁，或新开的 V-ID/ADR）
- 影响版本：macOS ____, Xcode ____, 提交 ____
```
