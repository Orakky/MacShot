# 待办台账（唯一真源）

> 状态词：`待裁决`（需用户签字）/ `blocked`（见 `blocked.md`）/ `open`（可领）/ `doing` / `已办`（移入 `done.md` 并留指针）。
> 领活规则见 `docs/protocol/agent-playbook.md`；**第 0 档全部完成前，任何编码类条目不得开工**（`docs/README.md` §4）。

## 第 0 档：文档裁决（当前唯一可做的工作）

| ID | 内容 | 需要谁 | 判据（怎么算完） | 状态 |
|---|---|---|---|---|
| T-001 | 签 Q-01（最低 macOS 14）→ ADR-003 转 accepted | 用户 | **已签 2026-11-16＝macOS 14**；同批签下 ADR-007/008/010 | 已办 |
| T-002 | 签 Q-02（默认热键）→ ADR-010 accepted + `keymap.md` 定稿 | 用户 | 三行默认值无 `待裁决` 标记；`MSSettings` 默认表与之一致 | 待裁决 |
| T-003 | 签 Q-03（9 件工具，含橡皮擦）+ Q-12（D-04 知情确认） | 用户 | `annotate-model.md` §4 表去掉 `待 Q-03`；`requirements.md#FR-ANN-002` 状态转 accepted | 待裁决 |
| T-004 | 签 Q-04（剪贴板表示）+ Q-05（提交动作语义） | 用户 | ADR-014 的实测矩阵填法被认可；`export-clipboard.md` §5 定稿 | 待裁决 |
| T-005 | 签 Q-06（P0 不落盘）+ Q-07（放大镜档位）+ Q-09（跨屏） | 用户 | `vision.md` G-04 与 NFR-005 措辞随之定稿 | 待裁决 |
| T-006 | 签 Q-11（改选区清空标注）+ Q-13（关闭二态）+ Q-10（`.idea/` 入库与否） | 用户 | 同上 | 待裁决 |
| T-007 | 签剩余架构 ADR：**002 / 009 / 011 / 012 / 013 / 014 / 015 / 016**（003/007/008/010 已于 11-16 签下） | 用户 | `docs/adr/README.md` 无 `proposed` 行 | 待裁决（009 与 013 已按你要求补"展开说明"） |
| T-008 | NFR §9 的 4 个取舍确认（回退线 / 键盘不闭环 / VoiceOver / macOS 26） | 用户 | `nfr.md` §9 全部转为决定或降级为 P1 说明 | 待裁决 |
| T-009 | 决定是否要可视化原型稿（HTML/图片）作为 `screens.md` 的对照物 | 用户 | 你已选"要"（2026-11-16）→ 交付见 `T-060`/E-014 | 已办 |

## 第 1 档：M-0 工程骨架（T-001…T-009 全绿后 open）

| ID | 条目 | 文件域（只许碰这些） | 判据 | 依赖 | 状态 |
|---|---|---|---|---|---|
| T-010 | 生成并验证 `MacShot.xcodeproj`（同步文件夹组 + 本地包引用 + 共享 scheme） | `MacShot.xcodeproj/`、`App/` | `xcodebuild -list` 能看到 scheme；build 成功；`App/` 新增空文件后**不改 pbxproj** 即被编译 | T-001 | **已办**（E-021） |
| T-011 | `Packages/MacShotKit` 10 模块 + 4 test target 空壳 | `Packages/MacShotKit/` | `swift test` 绿；`make check` 的依赖方向检查能报错 | T-001 | **已办**（E-021） |
| T-012 | `Config/Info.plist`（`LSUIElement`、`LSMinimumSystemVersion`、bundle id）+ entitlements | `Config/` | `make run` 后 Dock 无图标；`codesign -dv` 显示 adhoc | T-001 | **已办**（E-021） |
| T-013 | `Makefile` + `scripts/{doctor,build,test,run,dmg,check,reset-tcc}.sh` | `Makefile`、`scripts/` | 六个目标逐个跑通并把输出尾行贴进 `done.md`；无网络下 `make check` 通过 | T-010 | **已办**（E-021） |
| T-014 | 门禁脚本：风格 grep（禁 `try!`/`print`/中文硬编码/`URLSession`/像素用 `CGRect`）+ 依赖方向 + 文档一致性（P0 归属、ID 引用可解析、`screens.md` 中文串在 `MSStrings`） | `scripts/check-*.sh` | 每条规则都有"故意违规样例 → 报错"的自证用例 | T-013 | **已办**（E-021：三个门禁脚本） |
| T-015 | `MSCore` 几何与坐标实现 + 单测（`MSIntRect`/`MSDisplay.pixelRect`/`MSSelectionGeometry`） | `Sources/MSCore/`、`Tests/MSCoreTests/` | `nfr.md#NFR-010` 的换算表全绿；命中/钳制/翻转用例全绿 | T-011 | **已办**（E-021） |
| T-016 | `MSSettings` `AppPreferences` + 默认值表 + 单测 | `Sources/MSSettings/`、`Tests/MSSettingsTests/` | `FR-SET-003` 判据：清空 UserDefaults 后逐字段等于 `keymap.md`/`export-clipboard.md` 的默认表 | T-002,T-004 | **已办**（E-021） |
| T-017 | `MSTestSupport`：假采集器（测试卡位图）、假 pasteboard、假 hotkey 服务 | `Sources/MSTestSupport/` | 三个假实现都能被注入且被断言观察到（`overview.md` §7 的接缝 1/5） | T-011 | **已办**（E-021） |
| T-018 | 决定 `stash@{0}` 骨架的处置（逐条对照 accepted ADR：复用 / 参考重写） | 无（决策，写进 `done.md`） | 3 处不符（`modules.md` §12）逐条给出结论；不 `pop` | T-007 | **已办**（E-024/E-025：apply 后按 accepted ADR 改写） |
| T-019 | 根 `README.md` 重写为项目门面（现状 + 文档入口 + 裁决进度） | `README.md` | 新人能在 3 分钟内说出"当前在裁决期、不能编码"这一事实 | T-013 | **已办**（E-021） |

## 第 1.5 档：M-0.5 技术探针（T-001…T-009 全绿 + M-0 骨架可跑后 open）

> 先证伪再开工：这四条假设一旦错了就要返工整个架构（`docs/plan/roadmap.md` M-0.5）。代码只允许放 `spikes/probe-01/`。

| ID | 探针 | 文件域 | 判据（产出物） | 依赖 | 状态 |
|---|---|---|---|---|---|
| T-101 | 键盘与前台三态实测 | `spikes/probe-01/` | 一张"激活与否 × 键盘可达 × 前台是否变化"表；据此在 Q-15 选 A/B/C | T-010、T-012 | 待裁决 |
| T-102 | 贴图 level × collectionBehavior | 同上 | 最小可行 level 组合写入 ADR-019；若不可行则改 FR-PIN-001 承诺 | T-010 | 待裁决 |
| T-103 | `SCScreenshotManager` 单帧实测 | 同上 | 20 次 `t.hotkey→frozen` 读数 + 尺寸/scale/色彩核对，回填 ADR-007 判据 | T-010、T-012 | 待裁决 |
| T-104 | 签名与 TCC 授权稳定性 | `scripts/`、`spikes/probe-01/` | ad-hoc vs 本地自签证书各重装 2 次的授权保留表，回填 `permissions-tcc.md` | T-012 | 待裁决 |

## 第 2 档：M-1 起（只登记，未到档不许动）

| ID | 条目 | 里程碑 | 归属 FR/NFR |
|---|---|---|---|
| T-020 | `SCScreenshotManager` 主路 + 后端选择日志 | M-1 | FR-CAP-001/005、ADR-007 |
| T-021 | `LayoutSnapshot` 与会话绑定 | M-1 | FR-SESS-004 |
| T-022 | 权限探测 + 黑图启发式 + `UI-007` | M-1 | FR-CAP-006；顺带填 `hotkey-and-permissions.md` §5 的两个"待实测" |
| T-023 | `AnnotationDocument` schema v1 冻结 + 往返测试 | M-1 | ADR-009、NFR-018 |
| T-024 | 性能测量点内建（4 个 `t.*` 标记）+ `scripts/perf-snip.sh` | M-1 | NFR-001/002/003 |
| T-030… | 遮罩窗 / 指针路由 / 读数 / 状态机 / `CommitIntent` 与默认出口查表 / 剪贴板写入 | M-2 | FR-CAP-002/003、FR-SESS-001/002/003、FR-PIN-018、V-036 |
| T-040… | 贴图窗 level 实测（含 ADR-019 数值定稿）/ 缩放 / 透明 / `PinRegistry` | M-3 | FR-PIN-001…006/017 |
| T-050… | 渲染器三 intent / 9 件工具 / 命中 / 撤销栈 / 再编辑宿主 | M-4 | FR-ANN-001…007、FR-PIN-005 |
| T-060 | 可视化原型稿 `prototypes/index.html`：UI-001…009 可操作模型（**已办**，见 E-014） | 已完成（提前于 M-0，因为它服务裁决） | `docs/design/screens.md` 为真源，原型只是对照 |
| T-070… | 设置窗 / 重绑 / 免面板直存 / 本地化 / 对比度脚本 | M-5 | FR-SET-001…003、NFR-024 |
| T-080… | DMG / 兼容矩阵填满 / usage-report / 已知限制清单 | M-6 | NFR §5、vision §4 |

## 第 2.5 档：11-17 裁决直接产生的工作（顺序即建议顺序）

> 这一档不是我想加的活，是**签字换来的改动**。每条都写着"哪条裁决要它"，所以做完必须回写 `charter.md` §6b。

| ID | 条目 | 出处 | 文件域 | 判据 | 状态 |
|---|---|---|---|---|---|
| T-090 | **自签证书验证**：登录钥匙串建 `MacShot Dev`，在**副本**上签一次，量是否解除 `-3801` 预拒绝与重复弹框；不通过就撤销 | Q-18=A | `scripts/`、`Makefile`、`permissions-tcc.md` | 同一份源码重编两次，第二次采集**不再**返回 `-3801` 且不再弹框 ⇒ 通过；否则撤销证书并如实记 | open |
| T-091 | **剪贴板只写 PNG**：`MSClipboardWriter` 去掉 TIFF 表示 | Q-04 | `Sources/MSExport/`、`Sources/MSCore/`（协议）、`Sources/MSSettings/`（schema）、`App/`（`MSPNGItem`）、`Tests/MSSettingsTests` | ① 假 pasteboard 只收到**一个 PNG 载荷**且签名是 `89 50 4E 47` ② 真壳 `make probe-clipboard` 读出 `dpi=72×scale` 与 types 集合，并跑 `NSPasteboardItem` 对照组分清"我们写的"与"系统派生的" ③ v1 落盘文件（带已删字段）仍读得回来，热键与目录不回默认 | **done**（E-062；顺带否掉一条不可达的假判据：`NSPasteboard.types` 永远还会有系统派生的 `public.tiff`） |
| T-092 | **「置顶」＝贴出并写剪贴板**：`pin` 语义改造，`copyAndPin` 合并进 `pin` | Q-05 | `Sources/MSSession/`、`Tests/MSSessionTests/PinCommitCopiesTests.swift`、`docs/design/state-machines.md`、`docs/protocol/verification.md` | ① `Enter` 后同时出现贴图与剪贴板 PNG ② `Esc` 仍**不写**剪贴板 ③ `⌘C` 只复制不贴 ④ `ST-001` 行 11/12 与 `V-036` 随之更新 | **done**（E-063；顺带修掉"四个提交出口静默空转"的生产 bug——冻结帧被 `closeOverlay` 提前释放，违反 `ST-001` 行 14） |
| T-093 | **放大镜 + 取色进 P0**（`FR-CAP-016`）：跟随光标的取样窗、像素放大、`C` 复制 Hex、`⇧C` 切格式、`⌥` 强制呼出 | Q-07 | `Sources/MSOverlay/`、`Sources/MSCore`(已有 sampler)、`Tests/MSOverlayTests` | 放大镜内像素与屏幕逐点一致；`C` 复制串与取样色一致；贴边自动翻位不出屏；`W/A/S/D` **不做**（仍 P1） | open |
| T-094 | **工具条图标改 SF Symbols**：按 `design-system.md` §5 的核对表加载；折线箭头自绘 | B-027 | `Sources/MSAnnotate/MSAnnotationIcons.swift`（事实表）、`Sources/MSOverlay/{MSOverlayIcons.swift,MSOverlayView.swift}`、`Sources/MSPin/{MSPinIcons.swift,MSPinWindow.swift}`、`Tests/MSOverlayTests/IconResolutionTests.swift`、`scripts/imgcrop.swift` | ① 11 个工具全部取得到蒙版 ② 未知符号名 = `nil`（回落路径的前提）③ 逐工具量墨：16pt 格子非透明像素 ≥ 14 ④ 尺寸与着色按 `UI-002`（16pt、当前工具 accent、底色 accent @ 16%）⑤ `make probe-chrome` / `make probe-pin` 各目视一次 | **done**（E-064 + E-065；V-050 入册。装载器两份是 `B-031`，收拢要一条开模块的 ADR。`character.cursor.ibeam` 本机渲染成「文」，中文界面正好；换 macOS 版本符号名会漂移 ⇒ ①② 会变红，那是预期的提醒） |
| T-095 | **热键持久化实测**：改绑后重启软件/重启电脑仍在 | Q-02 | `App/`、`Sources/MSSettings/`、`V-037` | `V-037④` 填实：改绑 → 退出 → 再启动 → 旧键不响应、新键响应；写盘位置与格式在 `permissions-tcc.md`/`runbook` 有出处 | open |
| T-096 | **焦点还原实测（T-101）**：遮罩关闭后原 app 的前台与输入焦点都回来 | Q-15=A | `spikes/probe-01/`、`overlay-and-selection.md` §2、`V-006` | 四列真值表（激活与否 × 键盘可达 × 前台变化 × **原输入框可否继续输入**）；最后一列不成立就回到 Q-15 重签 | open |
| T-097 | **10 张贴图的内存读数** | Q-12 的安全阀、NFR-005 | `scripts/perf-snip.sh`、`done.md` | 读数进 `done.md`；破线即触发回 Q-12 复审，不许"记一笔继续做" | open |
| T-098 | **贴图编辑态撑高窗口**：图片下方长出一条工具带，工具与色板全在带里，画面与导出不被盖、不被缩（B-028 的最终形态，11-17 用户裁决） | B-028（11-17 再裁：撑高，否定折行） | `Sources/MSPin/MSPinWindow.swift`、`Sources/MSAnnotate/MSAnnotationToolbar.swift`、`Tests/MSPinTests/ToolbarFlowTests.swift`、`App/MSAppDelegate.swift`（`--probe-pin`）、`Makefile` | ① `200×140` 撑高后 `imageRect` 仍 140pt、窗口只长高、顶边不动 ② 编辑态导出的位图字节与非编辑态**逐字节相同** ③ 逐格量墨：每个格子与"同尺寸无工具带"渲染相比必须有墨 ④ 最后一行格子用合成鼠标事件点得到 ⑤ `60×40` 预算不够 ⇒ 不撑带、字母仍可用 ⑦ 编辑态 `zoom` 变化后带高 ≤ 图片高、窗口高＝图片×zoom＋带 ⑥ `make probe-pin` 出 `strip=78 image=(0,78,300,200) frame 高 278` + `build/probe-pin.png` 肉眼确认 | **done**（E-061；套件 121/121） |
| T-099 | **会话加"不呈现窗"测试入口**，让端到端判据不弹全屏窗 | B-029（11-17 裁） | `Sources/MSSession/`、`Tests/MSSessionTests/` | ① 走通 `Effect → 分发器 → onToast` 的自动化断言 ② 测试期间屏幕上**不出现**遮罩（这条本身要用日志或窗口计数证明，不能只靠"我觉得没弹"）③ 生产路径行为不变：`make probe-freeze` 仍绿 | **已办**（E-058；顺带抓到 `selectionDidChange` 是空函数这条死线） |

## 已知"提前做也没用"的项（防顺手实现）

- 窗口/元素自动识别（要动权限策略，P1，ADR-017）。
- 截图历史与 `.macshot` 落盘（Q-06 未定，P1）。
- 图像效果（圆角/阴影/水印）、贴图分组、鼠标穿透（P1/P2）。
- 任何 `CIFilter` 依赖的高斯模糊实现（ADR 未开，先用手写核或推迟）。
