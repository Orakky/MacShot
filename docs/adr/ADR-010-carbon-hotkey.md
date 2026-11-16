# ADR-010 全局热键实现：Carbon RegisterEventHotKey

状态：**accepted**（用户 2026-11-16 签字，并放开"可以索取辅助功能权限"这一策略） 相关：FR-HOT-001/002、ADR-015、`hotkey-and-permissions.md`

> **裁决记录与一处必须纠正的前提**：用户原话是"可以要辅助功能权限，为后续实时录制提前预留权限"。
> 但 **辅助功能权限打不开录屏**：屏幕内容的读取（截图与实时录制都算）只认 **屏幕录制** 权限；
> 辅助功能给的是另外两样东西 —— ① 全局键盘事件的拦截/注入 ② 读取其它 app 的 UI 元素树（Accessibility API）。
> 所以"为录屏预留权限"这个理由不成立；**放开权限本身仍然有价值**，但换来的是下面这些能力，已按此重新记账：
>
> | 放开辅助功能权限后新增可行的能力 | 对应条目 |
> |---|---|
> | 窗口/**界面元素**自动识别（Snipaste 的 `Tab` 检测，官方亦要求此权限） | `FR-CAP-011`（P1）、ADR-017 |
> | `W/A/S/D` 逐像素移动取样光标 | `FR-CAP-014`（P1） |
> | 未来若要"临时禁用贴图交互""全局按住键"这类交互 | 新 ADR |
> | **实时录屏** —— 与辅助功能无关，用 `SCStream` + 屏幕录制权限 | 属"明确不做"清单，需你单独解禁（章程 Q-17） |
>
> **热键实现不变**：仍用 Carbon `RegisterEventHotKey`。放开了权限不等于要用更贵的机制 ——
> `CGEventTap` 会让每条键事件穿过我们的进程（延迟与功耗），而 Carbon 零权限即可满足 FR-HOT-001/002。
> **P0 依然只索取"屏幕录制"一项权限**；辅助功能留到 P1 元素识别开工时才请求（提前请求只会让用户多一次无谓授权）。

## 背景
四大件的第一步必须在**别的前台 app 里**触发，且 MacShot 常态是后台 `LSUIElement`。要求：不额外索取权限、不常驻事件管道。

## 决策
Carbon `InstallEventHandler(GetEventDispatcherTarget())` + `RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(sig, id))`；回调里**只**做 `DispatchQueue.main.async` 派发；键码表集中在 `MSHotKey.KeyCodes`。

## 已考虑并否决的方案
| 方案 | 需要额外权限 | 否决理由 | 什么证据会翻案 |
|---|---|---|---|
| `CGEventTapCreate` | 辅助功能（**该权限已允许索取**，见上方裁决记录） | 否决理由改为纯技术账：每条键事件穿过我们的进程（功耗 + 延迟 + 系统输入链上的常驻钩子），而 Carbon 零成本就能满足需求 | 若出现"需要在其他 app 输入框里拦截/改写按键"的需求（元素识别不做这件事，它读 AX 树即可） |
| `NSEvent.addGlobalMonitorForEvents` | 输入监控/辅助功能 | 只读监听，不能消费，别的 app 同样收到该键（会误触发"亮度调节 + 截图"两件事） | 不会 |
| 第三方库 MASShortcut / KeyboardShortcuts | — | ADR-015（无 brew、不引第三方）未通过；且它们内部也是 Carbon | ADR-015 被 accepted 为"允许引依赖"时重评 |
| 菜单栏服务 / Automator 转发 | — | 多一层外部配置，用户装一次痛一次 | 不会 |

## 后果
正面：零额外权限（P0 只需屏幕录制一项，`hotkey-and-permissions.md` §4 的关键卖点）；行为与 Snipaste 同族实现一致。
负面：Carbon API 是旧框架（但 Apple 未提供等价替代且长期未变）；纯功能键（`F1/F3`）在 MacBook 上可能与系统媒体键冲突 → 需要 `fn` 或系统设置开关（Q-02 附带事实）；冲突只能靠返回码判断，**具体 OSStatus 数值待实测**。
连带义务：改绑时先注销后注册、失败回滚（`FR-HOT-002` 判据）；设置窗录制新键时必须先注销当前注册。

## 判据
1. 实拍：在 Safari 前台按 `F1` 能进遮罩（FR-HOT-001）。
2. 注册失败路径可观测：故意把 `F1` 给别的 app 占用，设置窗出现"注册失败"且日志有 OSStatus 值（填进本文，替换"待实测"）。
3. 睡眠唤醒后热键仍有效（`V-0xx`）。

## 受影响
`MSHotKey`、`docs/design/keymap.md`、`docs/runbook/troubleshooting.md`。
