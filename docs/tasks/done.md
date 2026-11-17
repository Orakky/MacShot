# 已办台账（附证据）

> 规则：**没有证据不写已办**。证据 = 命令输出尾行 / 文件路径 / 读数 / 实拍描述。日期用绝对日期。
> 已完成条目的正文迁到所属文档，本表只留一行 + 指针。

## 2026-11-16 文档裁决期（Wave 0：定范围）

| ID | 条目 | 证据 |
|---|---|---|
| E-001 | 环境事实核实 | `swift --version` → `Apple Swift version 6.2.4 … Target: arm64-apple-macosx15.0`；`xcodebuild -version` → `Xcode 26.3 (17C529)`；`xcrun --sdk macosx --show-sdk-version` → `26.2`；`sw_vers` → `15.7.4 (24G517)`；`ls /opt/homebrew/bin/brew` → `No such file or directory`；`security find-identity -v -p codesigning` → `0 valid identities found`。这些事实直接生成了 ADR-003/004/015 的结论 |
| E-002 | 4 项范围裁决取得（D-001…D-004） | 用户在会话中选择：只做四大件最小闭环 / 本机 ad-hoc 直装 / Xcode 工程 + 本地 SPM / 贴图携带可编辑标注层。已落纸 `docs/charter.md` §1 |
| E-003 | 过早写下的骨架收起（不是删除） | `git stash push -u -m "architecture-spike: …" -- Packages App` → `git stash list` = `stash@{0}: On main: architecture-spike…`；`git stash show --include-untracked --stat` = `9 files changed, 874 insertions(+)`；`find App Packages -type f` → 空。落纸为 `docs/architecture/modules.md` §12 的 3 处不符与 `T-018` 处置项 |
| E-004 | 文档宪法与地图落地 | `docs/charter.md`（范围/术语/模块/ID/Q 表/非谈判项）、`docs/README.md`（真源分配 + 冲突消解序 + 当前阶段判据）、`AGENTS.md`（纪律 + 命令 + 领活） |
| E-005 | 需求清单可裁决版落地 | `docs/requirements/requirements.md`：P0 带判据、P1、P2 与"明确不做 6 项"；准入纪律"无归属大件即降 P1"（`ADR-006`）。条数初稿写错（32/34），2026-11-16 审查订正为 §0 的 33/27，并把计数收敛到 §0 单一来源 |
| E-006 | Snipaste 事实核查（一手来源） | `docs/reference/snipaste-gap.md`，7 节全部带出处（docs.snipaste.com 的 getting-started / key-bindings / PRO / FAQ / Troubleshooting / Changelog + developer.apple.com 的 SCStream / SCScreenshotManager / CGWindowListCreateImage / CGDisplayCreateImage）；由后台研究 agent 取得（`【示例】研究助手`，32 次工具调用） |
| E-007 | 研究结论**推翻**了我先前 3 处假设并据此订正 | ① 取色不是 `F4`：官方是"放大镜可见时按 `C`"→ 改 `requirements.md#FR-CAP-012/013/014`、`keymap.md` §1/§2（原先写的"⇧+方向=10px"也是杜撰，官方是 `⌘`/`⇧`+方向做扩大/缩小）② 序号徽章与"二次编辑"是 Snipaste **PRO** 功能 → `charter.md` D-04 行加知情提示 + 新增 Q-12 ③ 剪贴板 PNG/TIFF 双表示**无官方出处** → Q-04 依据改为目标应用实测矩阵（`ADR-014`）④ 附加：橡皮擦是免费档功能而我漏了 → Q-03 从 8 件改 9 件 |
| E-008 | 架构层落地 8 份 | `docs/architecture/{overview,modules,capture-pipeline,overlay-and-selection,annotate-model,pin-window,export-clipboard,hotkey-and-permissions}.md`；含依赖图、坐标契约、渲染器三 intent、贴图 level 风险、内存粗算（4K 整屏 3840×2160×4 ≈ 33MB 为**粗算待实测**） |
| E-009 | ADR 16 条落地（4 accepted / 12 proposed） | `docs/adr/README.md` + `ADR-001`…`ADR-016`；每条含"已考虑并否决的方案 + 什么证据会翻案"（决策门），非只写结论 |
| E-010 | 设计层落地 4 份 | `docs/design/{design-system,screens,state-machines,keymap}.md`；UI-001…UI-009 逐屏线框 + 元素规格表 + 屏↔需求对照表（含已发现的缺口：多屏切换、贴图分组）；ST-001…ST-006 迁移与非法迁移用例 |
| E-011 | NFR 与愿景落地 | `docs/requirements/nfr.md`（NFR-001…036，全部标"目标值待实测"）、`docs/requirements/vision.md`（3 场景 + 5 个可观察成功指标 G-01…G-05） |
| E-012 | 计划与台账落地 | `docs/plan/roadmap.md`（M-0…M-6 准入/交付/准出判据）、`docs/tasks/todo.md`（第 0 档 T-001…009 为裁决项；编码档全部标 `待裁决`）、本文件 |
| E-013 | 2026-11-16 文档审查与补充（第二次通读，按"可证伪事实"核对） | 订正 6 类问题：① **NSWindow level 升序写错 2 处**（`overlay-and-selection.md` §1 把 `.screenSaver` 说成低于菜单栏；`pin-window.md` §1 把 `.modalPanel`(8) 排在 `.mainMenu+1`(25) 之后）② **需求计数错**：实际 P0=33、P1=27（原写 32/34），且 charter/README/ADR-006/done 各自复制 → 改为只引用 `requirements.md` §0 ③ **2 条判据不可执行**：FR-PIN-003"不同倍率同位置像素比对"、FR-ANN-006"屏上与导出逐像素一致" ④ **FR-SESS-003 把实现手段当需求**（"不激活 app"）→ 改为行为判据 + 新增 **Q-15** ⑤ 协议名不统一（overview 的 `Clock/FileSystem` vs modules 的 `MSClock/MSFileWriting`）⑥ `.gitignore` 缺 `.build/`（`swift test` 会在包目录生成）。**补充**：M-0.5 技术探针（`T-101…T-104`）、`B-014`/`B-015`、`design-system` 新增把手 token。证据：`git diff 4127a1e -- docs` |

## 2026-11-16 原型轮（T-009 → T-060）

| ID | 条目 | 证据 |
|---|---|---|
| E-014 | 可操作原型 `prototypes/index.html`（单文件、零依赖、零网络资源） | **量测到的事实**（浏览器内程序化驱动，非目测）：① `pixelRect({100.5,80.25,200.5,120.25})` @2x → `{201,161,401,240}`；naive `round(h×2)` 会给 241，差 1px —— ADR-013 的"两边分别取整"在原型里可见 ② 合成拖拽 (600,400)→(820,560) 落在既有选区内 → mode=`move`（判定顺序对），读数 `860×500 @2x` 与裁剪像素 `{500,340,860,500}` 同源 ③ 画箭头写入文档坐标 `(60,60)-(420,240)`（设备像素，y 向下）④ `⌘P` 提交后 `pin.elements=1` —— **D-04 的链路在原型里真的带过去了** ⑤ 贴图 zoom=2.5 时位图 backing 恒 `860×500`（不重采样）、矢量 backing `1075×625`＝860×2.5（按倍率重绘）、`image-rendering:pixelated` 生效 → 放大后"位图成方块、标注仍锐利"是可看到的 ⑥ 取色对假桌面真实采样命中 `#E83347`（就是那块饱和红）⑦ 9 屏 `paint()` 遍历无异常，把手计数 8。**修掉两个原型自身的 bug**：标注层 backing 多乘了一次 dpr（元素只会出现在左上 1/4）、贴图矢量层倍率算错（等于演示不出 D-04 的收益）；`.stage` 宽度由内容反推导致坍缩，改为固定 1200×760 逻辑舞台 + 外层 `transform:scale`。**原型不能证明的**：TCC 授权、window level 能否盖全屏、未激活窗口能否收键 —— 仍是 T-101/T-102/V-021 的活，右栏已逐屏标注"原型态 vs 待实测" |
| E-015 | 截图自查未做成 | `take_screenshot` 返回 `NATIVE_BROWSER_VIEWPORT_UNAVAILABLE … viewport=0x0, visible=false` → 内嵌浏览器无可视口，故改用 `evaluate_script` 做数值与路径核对。**视觉效果需你在真浏览器里打开这个文件看**，我没有目测过 |

## 2026-11-16 需求变更（用户提出"截图后可直接置顶"）

| ID | 条目 | 证据 |
|---|---|---|
| E-016 | 把"贴出"提升为一等出口：新增 `FR-PIN-018`、Q-05 推荐档由"复制"改为"贴出"、工具条主按钮与键位重排（`Enter`＝贴出、`⌘C`/`⌥Enter`＝复制、`⌘P` 保留）、默认出口改为查 `commitBehavior` 而非写进枚举语义 | 原型内程序化验证：按钮顺序读数 `贴出Enter* \| 复制⌘C \| 保存⌘S \| ✕`（`*`＝实底主按钮）；`Enter` → `pins 0→1`、`screen=UI-003`、选区已收；`⌥Enter` → `pins 1→1`（不新增贴图）且会话结束；设置默认档读数 `贴出*`。文档同步：`requirements.md` §0 计数 33→34、`charter.md` Q-05、`keymap.md` §2、`overlay-and-selection.md` §5、`export-clipboard.md` §5、`screens.md#UI-002`、`vision.md` S1、`verification.md` V-036 |

## 2026-11-16 架构裁决（第二批签字）

| ID | 条目 | 证据 / 后果 |
|---|---|---|
| E-017 | 签下 **ADR-003**（macOS 14）、**ADR-007 + ADR-008**（冻结快照、不做实时流）、**ADR-010**（Carbon 热键 + 辅助功能权限策略放开）；`adr/README.md` 计数改为 accepted 8 / proposed 8；章程 Q-01 标已签；`T-001` 转已办、`T-007` 缩到剩余 8 条 | 你的原话"采集的时候冻结快照，暂时不需要考虑实时"命中的是 ADR-008，ADR-007 是其下游结论，已在 ADR-007 顶部记明这一映射，并留了一个未决小格（是否保留 CG 兜底路径） |
| E-018 | **纠正一处权限误解并落纸**：辅助功能权限**不能**读取屏幕内容，录屏只认屏幕录制权限 | 写在 `ADR-010` 裁决记录 + `hotkey-and-permissions.md` §4；新增 **Q-16**（辅助功能权限何时索取，推荐 P1 再用时索取）与 **Q-17**（"实时录制"目前属"明确不做"，要不要解禁；`ADR-022` 占位） |
| E-019 | **ADR-013 的算术自我纠正**：用 `ROUND_HALF_UP`（等价 Swift `.rounded()`）实测 20 组坐标 | 结论：**2x 下"两边分别取整"与 naive 完全一致**；差 1px 出现在 **1x + 半点坐标**（x=100.5,w=200.5 → 201 vs **200**；x=0.5,w=100.5 → 101 vs **100**；x=64.5,w=37.5 → 38 vs **37**）与 **1.799x**（361 vs **360**）。本 ADR 早先"这是为非整数缩放准备的"表述不准，已在 ADR-013 与 `capture-pipeline.md` §4 改正：它是每次选区都要走的路径，不是外接屏特例 |
| E-020 | ADR-009 / ADR-013 补"展开说明"章节供你裁决 | ADR-009 展开：这条实际决定 ①内存类型形状 ②将来序列化的字节契约 ③版本兼容策略三件事，JSON 换回来的是"夹具能手写 + 出问题能 `cat` + diff 可读"，代价约 3–4KB/20 元素（估算待实测）；并把问题收敛成两个：是否接受字段只增不改语义、是否接受 M-1 冻结 |

## 2026-11-16 M-0 落地（编码开闸）

| ID | 条目 | 证据 |
|---|---|---|
| E-021 | 工程骨架可运行：`App/` + `Config/` + `MacShot.xcodeproj`（同步文件夹组）+ 10 模块 SPM 包 + `Makefile` + 3 个门禁脚本 | `make check` 全绿：doctor 通过 → check-style/deps/docs 通过 → `Test run with 47 tests in 14 suites passed` → `** BUILD SUCCEEDED **` → 产物 `build/Derived/Build/Products/Debug/MacShot.app`。ADR-001 的核心前提得证：新增 `App/main.swift` 的探针分支**未改 pbxproj** 即被编译 |
| E-022 | 首次真机采集（M-1 地基） | `MacShot --probe-capture` → `permission=granted`、`displays=KG251Q:1920x1080@x1.0px1920x1080`、`backend=screenCaptureKit`、`degenerate=false`、5 次耗时 `0.133/0.081/0.082/0.080/0.079 s`、中心像素 `#27272C`。ADR-007 主路成立；NFR-001 的 300ms 预算里纯采集只占 ~80ms |
| E-023 | 热键注册与冲突路径实测 | 启动日志 `registered 1 = F1` / `registered 2 = F3` / `registered 3 = ⌘A`；冲突实测 `OSStatus=-9878`（B-004 关闭：真实值不是 -9877） |
| E-024 | 修掉会毁掉默认体验的 bug：`functionKey(122)` 把 keyCode 当 F 序号查表 → 落空返回 0 → **F1 被静默注册成 A 键**，第二条热键随之冲突 | 现象来自日志读数 `registered 1 = A`（不是读代码看出来的）。修法：`functionKey(_:)` 只接受 1…12 且越界 `preconditionFailure`，另加 `.f1/.f3` 常量；回归断言 `hotKeys.snip.display == "F1"` 已进 MSSettingsTests |
| E-025 | `MSCore` 去掉 `import AppKit` | 被 `check-deps.sh` 拦下后，把屏幕清单枚举移到 `MSCapture.MSDisplayInventory`；`MSCore` 回到纯值类型，显示器列表同时变成可注入参数（测试接缝变好） |
| E-026 | M-0 未覆盖 | 遮罩的拖框/标注/提交需人手验证；V-003 粘贴矩阵、V-010 层级、V-006 键盘与前台均未测；本机单屏 1x，Retina/2x 与多屏路径在此机无法证伪 |

## 2026-11-16 热键改绑 + 左键截图

| ID | 条目 | 证据 |
|---|---|---|
| E-027 | `FR-HOT-002` 改绑（录制→校验→注册→失败回滚→持久化）+ `FR-HOT-013` 左键直接截图、右键出菜单 | `make build` 通过；重启日志 `registered 1 = F1 / 2 = F3 / 3 = ⌘A`；新增 5 条 `MSKeyBindabilityTests`，套件从 47 → **52 条**通过 |
| E-028 | 测试抓出两个自己的错 | ① `bindability()` 把 **keyCode 0（A 键）当成"未知键"** → 等于谁都绑不了 `⌘A`，而我们默认的全屏截图正是它；改为按 `keyNames` 表判定，并加断言 `⌘A` 可绑定 ② 我误以为显示次序是 `⌘⌥`，Apple 规范是 `⌃⌥⇧⌘` → 是测试期望写反，已按规范固定 |

## 2026-11-16 严重缺陷：截图后 Esc 退不出（遮罩锁屏）

| ID | 条目 | 证据 |
|---|---|---|
| E-029 | 根因定位并修复：`perform(effect)` 的 `default: break` 静默吞掉 `.closeOverlay`，状态机已正确产出该 effect（`V-008` 行 13 一直是绿的，所以单测没拦住），但没人执行 → 遮罩不收、整屏吃点击，只能 ssh 杀进程 | 定位方式＝读 `perform` 源码 + 确认 reducer 输出含 `.closeOverlay`；修法＝**删掉 `default` 改为穷举**（以后新增 effect 不处理就编译不过），并把另两处 `default: break`（权限分支、intent 分支）也改成显式列举 |
| E-030 | 三条逃生阀（不再依赖"键一定要收到"）：① 遮罩开着再按 `F1` = 取消 ② app 失去活跃状态自动收窗 ③ `cancelSession()` 幂等，且状态机拒绝迁移时也强制关窗 | `MSSessionCoordinator.cancelSession/overlayVisible`；`MSAppDelegate.observeResignActive` 与 `snip()` 的 toggle 分支；单测 5 条 `EscapeHatchTests` 覆盖 frozen/selecting/editing/失败四种取消路径必须含 `.closeOverlay` |
| E-031 | 制度性补强：`check-style.sh` 新增拦截 `default: break`；`coding-conventions.md` 新增 §4b「分发器必须穷举」；`AGENTS.md` 纪律第 11 条；评审清单加第 11 问 | 新规则一上线就在旧代码里查出 3 处真实空转（已修），证明它抓得住同类形状 |
| E-032 | 套件与门禁 | `Test run with 57 tests in 16 suites passed`（47 → 52 → 57）；`make check` 全绿；`make build` 无 warning；重启后日志 `registered 1 = F1 / 2 = F3 / 3 = ⌘A` |


## 2026-11-16 权限阻塞（B-021）

| ID | 条目 | 证据 |
|---|---|---|
| E-033 | 撤回我此前的错误结论：E-022 说"已验证真机采集"，实际是**在终端里跑二进制、继承了 Terminal 的屏幕录制授权**，不能证明 MacShot.app 自身可用 | `open MacShot.app --args --snip-now` → `preflight=denied` + `SCStreamErrorDomain -3801 用户拒绝了…TCC`，35ms 返回且无系统弹窗；`make install` 到 `~/Applications` 后同样；`tccutil reset` 后同样 |
| E-034 | 修掉我自己造的**死锁**：`startSnip()` 原先在 preflight=denied 时直接弹引导窗并放弃采集，而 macOS 只在应用真的尝试采集时才把它写进「屏幕录制」列表 → 越检查越无法授权 | 现在无论如何先试一次采集；失败按 `-3801` 归类为权限缺失 → 调 `CGRequestScreenCaptureAccess()` + 引导窗；引导窗新增「清除旧授权记录」按钮（`MSTcc.resetScreenCapture`，参数全常量） |
| E-035 | 错误分类与文案 | 新增 `MSCaptureError.isPermissionDenied/describe` + `MSCaptureTests` 4 条（套件 57 → **61**）；一次失败只出一条提示，`Error Domain=…` 原文不再出现在用户界面 |
| E-036 | `Esc` 无效的真根因取证（不是"候选"）：日志 `overlay claimKey#0 key=false responder=true` → 31ms 后 `claimKey#1 key=true`。两因叠加——① `MSOverlayView` 从未被选为 first responder（`acceptsFirstResponder` 默认 false，borderless 窗不自动选人）→ `keyDown` 压根没被调用；② `present()` 只抢一次 key，而 `NSApp.activate` 是异步的 | `MSOverlayView` 覆写 `acceptsFirstResponder`/`becomeFirstResponder` + `makeFirstResponder(overlayView)`；`claimKey(attempt:)` 30…500ms 递进重试（每次记日志，上限 6 次）+ 本地键监视器 + 全局 `Esc` 观察器。判据：`V-006` 以 `claimKey#N key=true` 为通过条件 |
| E-037 | 遮罩加**三条纯鼠标出路**（键盘万一不通也不至于被锁在屏幕外）：左上角常驻 ✕（`OverlayChrome.cancelHitRect`，可视 28pt／命中 44pt）、右键任意处取消、再按一次截图热键取消；`teardown()` 必摘本地/全局监视器 | 新增纯函数 `OverlayChrome`（坐标系与命中区可单测）+ `OverlayChromeTests` 4 条；`perform(effect)` 删掉 `default: break`（就是它吞了 `.closeOverlay`），规范 §4b 从此禁用该写法。套件 61 → 65 |
| E-038 | 修"每次启动都问权限"里属于我的那半边：拒绝路径原来每次都调 `CGRequestScreenCaptureAccess()`，每按一次 `F1` 就再敲一次门 | `MSSessionCoordinator.requestPermissionOnce()`：每个进程生命周期只申请一次，之后只走引导窗；系统申请做成可注入 `permissionRequester`（单测因此能跑拒绝路径而不真弹框）+ `PermissionThrottleTests` 断言 3 次调用只申请 1 次。套件 65 → **66**。剩下那半边是签名身份，见 Q-18 / P-002 |
| E-039 | 把"ad-hoc 每次重编都换身份"从推断做成对照实验：**源码一字未改**，只 `make clean && make build` | 二进制 sha256 `5f074f41…`→`fdc887c9…`；`codesign -d -r-` 的 `designated => cdhash H"0f85ca84…"`→`H"ec5d7ed3…"`。ad-hoc（`TeamIdentifier=not set`）能匹配的就是这一串 hash ⇒ 重装/重编必失效，**Q-18 的 B（手工重勾）在开发循环里不可用**，能救的只有稳定身份（A 自签证书 / C Developer ID）|
| E-040 | Q-18 你裁定 **B**（不建证书、不碰钥匙串）⇒ 日常入口做成 `make run-term`：build 后直接 `exec` 产物二进制，先杀旧进程 | 实测同一 PID 起来就有 `launched version=0.1.0 scale=1.0` → `capture.backend=screenCaptureKit` → `registered 1 = F1` / `2 = F3` / `3 = ⌘A` → `ready hotkeys=F1/F3`；读日志必须带 `--info`（`log show --last 1m --info --predicate 'subsystem == "com.macshot.app"'`，不带 `--info` 是空的，我踩了一次）。**边界写进 runbook**：这条路借的是终端的授权，不能当 .app 自身可用的证据（V-021 仍开）|
| E-041 | 品牌图形接进运行时：菜单栏不再是 `✂` 文本。关键取证是**AppKit 能直接把 SVG 当矢量资源用**，所以不做 PNG 副本、图形只有一份真源 | 探针 `NSImage(contentsOf: svg)` → `size=(24,24)`、重画 18×18 `inkCoverage=0.346`；实跑日志 `status glyph=18.0pt template ink=0.31`；**实拍菜单栏前后两张**（`screencapture -x -R0,0,1600,26`）差异 bbox 高正好 18px、changed=2950，放大图目视＝描边屏幕＋右上角实心块。新增 `MSStatusGlyph`（含"画得出东西"的墨量断言）+ `StatusGlyphTests` 2 条，套件 66 → **68** |
| E-042 | 修状态栏权限行**只刷新一次**的失效：`item(withTitle:"屏幕录制权限：检测中…")` 在第一次写完后必然查不到（标题已变成结果）⇒ 常驻读数停在首值 | 改为持引用 + 日志**回读** `permissionMenuItem?.title`（拿到 nil 就说明没握住）；新增 `--probe-menu` 诊断，实跑 `probe-menu#0/#1/#2 rows=10 attached=true` 三次连续刷新都命中同一行。判据形式记进 `brand.md` §2 与规范"常驻读数行要先证它这次换过话" |
| E-043 | 品牌事实落纸：新增 `docs/design/brand.md`（文件边界 / 装载实测 / 管线 / 两项未过目），登记进 `docs/README.md` §2；`screens.md` UI-006 的"`scissors` 待核对"随之了结。构建侧收口：`inject-brand.sh` 统一注入（原 `appicon`/`dmg` 两处重复的 cp+重签合一），`run/run-term/probe/dmg/install/check` 全部改走 `appicon`，入口不再跑在缺素材的 bundle 上 | `make icon` 实测出 1024 母版 + 104K `.icns`（最大层 1024px）、`codesign --verify` OK、`CFBundleIconFile=macshot` 生效 |
| E-044 | 实拍发现**看得见的 ✕ 在左下、点得到的 ✕ 在左上**：`OverlayChrome` 的命中区与四条单测都是对的，错在 `drawCancelButton` 自己又换算了一次 y（`bounds.height - visual.maxY`）。等于鼠标那条退出路径指向一片空白 | 修法是把坐标真相收回到一处：`OverlayChrome.cancelPaintRect/cancelHintOrigin`，视图内不再有任何换算。新增 `OverlayPaintTests` 用 `cacheDisplay` **离屏渲染后量像素**（阈值：命中区墨量 > 0.08、左下镜像 < 0.02；断言方向反了也会红——我第一版测试就把视图 y 直接当位图行号用，量反了）。闸口自证：临时装回旧换算 → `top=0.0 / bottom=0.32` 两条失败；还原 → 绿。套件 68 → **72** |
| E-045 | 遮罩暗化层与规格不符：`design-system.md` §2.1 定的是 `overlay.scrim` 浅 45% / 深 55%，代码里却是我自造的"无选区 0.35 / 有选区 0.45"两个数（实拍反推 alpha≈0.365 才发现） | 改为 `OverlayChrome.scrimAlpha(isDark:)` 按外观取 token，两条绘制路径共用一个值。实测（深色档，三处静态区亮度比）0.440 / 0.434 / 0.440 ⇒ 反推 0.560 / 0.566 / 0.560，与 55% 在舍入误差内。判据落 `V-040`，数值单源仍在设计系统表 |
| E-046 | 开了一条**实拍取证通道**：`screencapture -x -R…` 出 PNG + 我直接读图目视 + 自写亮度/差异脚本（`/tmp/imgdiff`）。E-015 那个"没有可视口、视觉未经目测"的缺口，原生界面这半边从此可验 | 用它当场量出：遮罩下菜单栏文字条亮度比 0.440，与 Dock 0.440 / 左栏 0.434 同档 ⇒ 遮罩窗（`level = statusBar+1`）**盖在系统菜单栏之上**，所以顶部 24pt 可以被框选（FR-CAP-002，判据 `V-041`）。同时纠正一次误判：我眼看缩略图以为"遮罩没变暗"，量出来是降了 36%，目视在缩略图上不可靠 |
| E-047 | P0 工具面补到 8/9 件：`N` 序号徽章与 `E` 橡皮擦在遮罩内可用；顺带修掉一个自造的键位冲突——`rect` 之前占的是 `R`，而 `keymap.md` §2 把 `R` 分给「重复上次区域」（P1），真源是 `M` | `MSTool` 加 `badge/eraser` + `isClickAction`；徽章的 `insert` 与 `badgeCounter` 打包成**一条** composite（撤销不留空号）；橡皮擦删 z 最大的命中元素、**没命中就不入栈**。新增 `AnnotationToolTests` 3 条（套件 72 → **75**）。过程中实测出两条语义并写进 `annotate-model.md` §4：未填充形状的命中区是轮廓而非内部（我第一版测试点在框心里，橡皮擦当然删不掉）；空点压记录会让用户多按一次 `⌘Z`。`document/history/performClickAction` 从 private 降为 internal 当测试缝。缺的那一件是 `T` 文字（field editor），已开 B-024 |
| E-048 | 文字工具 `T` 接入（B-024 关闭）：ST-003 的「文字输入」子态按规格实现——`Enter`/`⌘Enter` 提交、`⇧Enter` 交回 field editor 换行、`Esc` 只退子态不退会话且不入撤销栈、空文本不入记录、再编辑走 `replace` 保 id | 新增 `MSIntPoint.canvasPoint/viewPoint`（成对逆运算，MSCore）+ 往返单测 ×4 scale 漂移 ≤ 半像素；`TextEditingTests` 7 条（`CanvasViewRoundTripTests` 2 + `TextEditingTests` 7，套件 75 → **84**），按键用 `CGEvent → NSEvent(cgEvent:)` 合成后喂真实 `handleKey` 路由。测试过程自己抓到一个错：我先把 keyCode 17 当成 `A`（其实是 `T`），改正后顺手把「`T`＝文字」也断言进去。`⌘C/⌘V/⌘Z/删除` 在子态内一律不消费，交回 field editor |
| E-049 | 工具条几何收成一个真源，并**订正 B-025 的诊断**：原写"窄选区会丢按钮"是错的——条宽跟**屏宽**走，窄选区不丢按钮；真缺陷是①贴右边的选区会把整条推出屏幕（没有 x 钳制）②`drawToolbar` 与 `hitToolbar` 各算一遍 x、且各有一套截断规则（画不出但仍可点＝隐形命中区，和 ✕ 同形）③旧公式算的 638pt 少算了两侧内边距，实测 654pt | 新增 `MSOverlayToolbar`（纯几何：`layout`/`naturalWidth`/`readoutOrigin`），绘制与命中同取一份 `Layout`；`ToolbarLayoutTests` 7 条钉住：60/120/320/640pt 选区工具数不变、x=1200…1910 时 `rect.maxX ≤ 屏宽-6`、每个工具格都在条内、格子互不重叠且顺序＝工具表、600pt 屏先收键位文字不收工具 |
| E-050 | 开第二条目视通道 `make probe-chrome`：把遮罩 chrome **离屏自绘**成 PNG（合成棋盘底，不采集 ⇒ 不碰 TCC、不弹权限、不需要鼠标事件）。第一次就看到工具条/读数/把手/✕ 的真布局，并抓出一个数值断言永远拦不住的遮挡 | 实拍图显示**尺寸读数被工具条压住**：规格 UI-001 第 5 行写的是"右下外侧 8pt，越界翻内侧"，而外侧正是工具条的地盘 ⇒ 实现按规格翻内侧（`readoutOrigin`，同帧先算工具条再画读数）。改后自绘图上 `420×260` 清楚可见。另：我两次把测量假象当成缺陷（缩略图以为没变暗；左边 6px 白以为是描边过粗，其实是左中把手），已按"先量再判"记进流程 |
| E-051 | M-4① 渲染基线落地，并**当场抓出一个用户级缺陷：文字与序号里的数字一个像素都画不出来**。根因在渲染器不在工具层——元素层已经是 y-down 文档空间，`drawText` 的反翻却又用了负的文档 y（`translateBy(y: -(origin.y + …))`），整段字被推到画布外；`drawTextCentered`（序号数字）同错。工具层测试全绿是因为它们断言的是**文档内容**（`element.text` 可读），不是像素 | 新增 `RendererSnapshotTests` 3 条：8 件几何/像素类工具 × `preview`/`pin`/`export` 共 **27 张基线 PNG**（`Tests/Fixtures/baselines/`，144K，逐像素容差 0）+ 每件工具墨迹包围盒与几何一致 + `text`/`badge` 走结构断言（字形随系统字体版本变，钉字节会造出一台机器才绿的雷，理由写在文件头）。重生成：`MACSHOT_SNAPSHOT_UPDATE=1 swift test --filter RendererSnapshotTests`，**生成后必须人眼看**。修完文字后 27 张基线 sha256 一字未变 ⇒ 修复没渗进别的路径。目视还暴露底图太平滑（高斯看不出），已加 4px 棋盘高频区。套件 91 → **94** |
| E-052 | 教训登记：**「工具接上了」不等于「看得见的东西画出来了」**。E-048 那批 7 条测试证的是按键路由与文档状态，渲染产物从未被像素级看过；同一天基线快照一跑就抓到文字空白。同类形状此前已出现两次（✕ 位置、读数被工具条压住）：**纯逻辑与纯几何断言看不见「最终画面上有没有东西」** | 从此界面类改动必须至少过一条像素判据（基线、墨迹包围盒、离屏渲染占比或实拍），否则不许写「已接」。这条写进 `V-044` 与 `annotate-model.md` §5 的判据纪律 |
| E-053 | M-2 准出 ①④ 首次拿到运行时读数：遮罩期间背景确实冻住、取消路径确实不碰剪贴板。过程里探针自己错了两次，两次都是**判据设计**的错，不是产品的错——值得记下来 | ① 第一版按固定 `sleep 0.7` 拍，第一张其实拍的是实况桌面（与 `before` 只差 0.6%），被误报成"背景在动"；改成**等 `overlay shown` 日志再连拍**。② 第二版整帧比较报 `changed=9 bbox=1908,4..1914,10`，裁图目视确认是 macOS 录屏指示器在脉动（画在所有窗之上），于是比较只排除那一小块并**把排除量单独打印**，不悄悄忽略。最终读数：三连拍两两 `IDENTICAL`（517945 采样点）、遮罩帧与实况差 485547/518400（证明遮罩真起来了）、哨兵 string 与 pngBytes 原样、日志 `cancelled from selecting, now idle`。新增 `make probe-freeze` + `scripts/{probe-freeze.sh,imgdiff.swift}` + `--snip-then-cancel` 诊断入口 + `CancelSentinelTests` 2 条（假剪贴板 `writeCount==0`，含防空断言与"复制出口必须真写一次"的对照）。套件 94 → **96** |

## 尚未完成 / 未验证（写清楚，避免被当成已完成）

1. **可交付物尚未成立**：代码已能构建（M-0 落地，`make check` 全绿，套件 **66**），但**当前装的还是旧版**——`~/Applications/MacShot.app`（cdhash `a92824b4…`）不含 E-036/E-037 的 `Esc` 与 ✕ 修复；受 B-023 约束，Q-18 未答复前我不再 `make install`。
2. **macOS API 行为：部分实测、部分仍空**。已取证：屏幕录制拒绝码 `-3801`（E-033）、单帧采集延迟 79…133ms（E-022 复测）、`RegisterEventHotKey` 冲突码 `-9878`、遮罩 key 抢取的 `claimKey#0 false → #1 true`。**未测**：贴图在全屏 Space 上的可见性（T-101/V-010）、Retina 2x 与非整数缩放与多屏（B-016，本机只有 1 块 1x 屏）、剪贴板跨 app 矩阵（V-003）。
3. **原型的视觉观感未经目测**：E-015 说明了原因（无可视口）。它证明了数学与状态路径，不等于"看起来对"——第一次在真浏览器里打开时请顺手校对：工具条是否压住选区内容、贴图投影与角标位置、设置窗 460pt 是否够用。
4. `.gitignore` 已建立（忽略 `build/`、`.build/`、`.idea/`、`*.app`、`*.dmg`；`Tests/Fixtures/**/*.png` 例外保留）。Q-10 仍待你确认 `.idea/` 是否真按推荐忽略。
5. 提交记录：`4127a1e`（文档集）→ `c6f819b`（审查修订）→ 本轮原型为第三个提交；`git push` 由你在终端执行。
