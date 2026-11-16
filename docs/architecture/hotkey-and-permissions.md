# 全局热键与权限

> 机制真源：热键注册/派发的事件链路与 TCC 权限检测。默认键位是裁决项（Q-02）；实现方案是 ADR-010（`proposed`）。

## 1. 为什么必须"全局"

四大件的第一步（快速截图）要求在**别的前台 app 里**触发（FR-HOT-001）。因此 MacShot 常态是 `LSUIElement` 后台进程，热键必须系统级注册，不能靠 `NSWindow` 的 key equivalent。

## 2. 方案对比（正文论证在 ADR-010，此处只给结论表）

| 方案 | 需要额外权限 | 可靠性 | 结论 |
|---|---|---|---|
| Carbon `RegisterEventHotKey` | 无（不需要辅助功能） | 系统级、成熟、Qt/Electron 截图工具同源做法 | **采用** |
| `CGEventTapCreate` | 辅助功能（Accessibility） | 能拦能改，但每次事件都过我们进程，延迟与功耗风险 | 否决（除非将来要做"键位重映射"类功能） |
| `NSEvent.addGlobalMonitorForEvents` | 输入监控 / 辅助功能 | 只读，拿不到消费权，别的 app 也会收到同一个键 | 否决 |
| 第三方快捷键库（MASShortcut / KeyboardShortcuts） | 视实现 | 封装的是 Carbon | 否决：ADR-015 未通过（本机无 brew，且不引第三方依赖） |

## 3. 实现要点（M-1 落地时的注意清单）

```swift
// 关键约束，不是可选项
EventHotKeyID(signature: OSType(macshotFourCC), id: HotKeyID.rawValue)
GetEventDispatcherTarget() + InstallEventHandler(callbackURL: nil, handler, 1, &outRef)
handler 内：只做一件事 —— DispatchQueue.main.async { 触发 }   // 回调上下文不能碰 UI，不能抓取
```

| 点 | 规则 |
|---|---|
| keyCode 常量 | 集中一张表（`F1=122`、`F3=99`、`A=0`…），禁止散落魔数；表由 `MSHotKey` 拥有 |
| modifier | `cmdKey/shiftKey/optionKey/controlKey`，⌘ 与 ⌃ 必居其一**或**纯功能键（Snipaste 默认 `F1` 就是纯功能键，所以不能强制要求修饰键） |
| 纯功能键风险 | MacBook 上 `F1/F3` 默认是亮度/Mission Control，需 `fn` 或在系统设置开启"作为标准功能键"→ 设置窗必须显示这行提示（Q-02 附带事实，`UI-005`） |
| 冲突 | `RegisterEventHotKey` 返回"已存在"错误时 → 置 `conflicts`，状态栏标记 + 文案（P1 `FR-HOT-011`；P0 至少记日志并在设置窗显示"注册失败"）。具体 OSStatus 数值**待实测**（`T-004`） |
| 重绑 | 改设置时：先全部 `UnregisterEventHotKey` → 注册新集合 → 失败则回滚旧集合并报错（不许出现"新旧都能触发"或"全都失效"）（FR-HOT-002） |
| 录制控件 | 设置窗里按新键时，**先注销**该 id 的旧注册，否则会被自己吞掉（这是自测才能发现的坑，写在这里） |
| 睡眠/唤醒、退出 | 监 `NSWorkspace.willPowerOff`/`didWake`；退出前注销全部（FR-HOT-001 稳定性） |

## 4. 权限地图

| 能力 | 权限 | 从哪个系统版本起必须 | 出处 | 首版是否涉及 |
|---|---|---|---|---|
| 抓取屏幕内容 | **屏幕录制**（TCC ScreenCapture） | macOS 10.15 Catalina 起 | Snipaste 官方故障排查 S5（`docs/reference/snipaste-gap.md` §6） | 是，P0 必需 |
| 窗口/界面元素自动识别 | 辅助功能（Accessibility） | — | 同上 | **权限策略已放开**（ADR-010，2026-11-16）；索取时机待 Q-16。功能本身仍是 P1 `FR-CAP-011` + ADR-017 |
| `W/A/S/D` 逐像素取样光标 | 辅助功能 | — | 同上 | 同上（P1 `FR-CAP-014`） |
| 全局热键 | 无 | — | Carbon 路径 | 是 |
| 剪贴板读写 | 无 | macOS 会显示"某某应用读取了剪贴板"提示（只对部分目标） | 待实测 | 是 |
| 写入 `~/Pictures` | 无（非沙盒，D-02） | — | ADR-004 | 是 |
| 开机自启 | 无（`SMAppService`） | macOS 13 起 API | 待实测（ADR-020 占位） | 否（P1） |

**P0 只需要一项权限：屏幕录制。** 这条要写进引导文案——权限越少越好用是这类工具的关键体验。

> 一句话分清两项权限，避免"提前留权限"的错觉：**屏幕录制＝看得见屏幕内容**（截图、录屏都靠它）；
> **辅助功能＝能拦键 + 能读其它 app 的界面元素树**（元素识别、像素光标、键位重映射靠它）。
> 因此"为了以后做实时录制而先要辅助功能权限"是无效路径——录屏只要屏幕录制权限，而且录屏目前属"明确不做"（章程 Q-17）。

## 5. 屏幕录制权限的检测与引导（FR-CAP-006 的落地）

| 步骤 | 做法 | 备注 |
|---|---|---|
| 1. 探测 | 优先 `CGPreflightScreenCaptureAccess()`；若目标系统不可用则退化为"试抓一帧 + 退化判据" | 该 API 的可用最低版本**待实测**（`T-004`），确认前先不假定 macOS 14 一定有 |
| 2. 申请 | `CGRequestScreenCaptureAccess()` 会把用户送到系统设置对应面板 | 是否真能弹系统授权框、还是只跳设置，**待实测** |
| 3. 退化判据 | 抓取结果与壁纸逐块比对 / 全黑 → 判为未授权 | 启发式，需实测校准，绝不允许把黑图当成功 |
| 4. 授权后 | 屏幕录制授权变更**通常需要重启进程**才生效 → 引导窗提供"重启 MacShot"按钮 | 是否必须重启、能否热重载，**待实测** |
| 5. 复位 | `scripts/reset-tcc.sh`（`tccutil reset ScreenCapture com.macshot.app`）供排查 | 见 `docs/runbook/permissions-tcc.md` |

## 6. 键位默认值（受 Q-02 裁决）

| 动作 | 推荐默认 | Snipaste 官方对应 | 备注 |
|---|---|---|---|
| 截图（进遮罩） | `F1` | `F1` | |
| 把剪贴板图像贴出 | `F3` | `F3` | 四大件②的入口 |
| 全屏截图（整屏直出） | `⌘A` | `⌃A`（macOS 以 `⌘` 替换 `⌃`，官方 S2 页首说明） | ⚠ `⌘A` 与"全选"撞车概率高，若实测困扰改 `⌥⌘A` |
| 隐藏/显示所有贴图 | `⇧F3`（P1） | `⇧F3` | |
| 重复上次区域 | 遮罩内 `R`（P1） | `R` | |

键位真源表在 `docs/design/keymap.md`；本表只说明默认值的出处与风险。

## 7. 测试接缝

- `HotKeyServing` 协议 + `FakeHotKeyService`：会话对热键事件的响应可在无头环境测（喂事件 → 断言 Effect）。
- 真实注册/冲突/`fn` 键行为只能在实拍测（`V-001`），必须写清"哪台机器、哪个键盘、系统设置里功能键选项状态"。
- 权限路径：`tccutil reset` 后的首启行为属固定回归项（`V-002` 之后编号由 `docs/protocol/verification.md` 分配）。
