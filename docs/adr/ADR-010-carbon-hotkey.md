# ADR-010 全局热键实现：Carbon RegisterEventHotKey

状态：**proposed** 日期：2026-11-16 相关：FR-HOT-001/002、ADR-015、`hotkey-and-permissions.md`

## 背景
四大件的第一步必须在**别的前台 app 里**触发，且 MacShot 常态是后台 `LSUIElement`。要求：不额外索取权限、不常驻事件管道。

## 决策（建议）
Carbon `InstallEventHandler(GetEventDispatcherTarget())` + `RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(sig, id))`；回调里**只**做 `DispatchQueue.main.async` 派发；键码表集中在 `MSHotKey.KeyCodes`。

## 已考虑并否决的方案
| 方案 | 需要额外权限 | 否决理由 | 什么证据会翻案 |
|---|---|---|---|
| `CGEventTapCreate` | 辅助功能 | 每条事件过我们进程（功耗/延迟），且要为一个截图工具索取辅助功能权限不值得 | 若出现"需要在其他 app 输入框里拦截键"的需求（当前没有） |
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
