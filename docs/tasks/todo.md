# 待办台账（唯一真源）

> 状态词：`待裁决`（需用户签字）/ `blocked`（见 `blocked.md`）/ `open`（可领）/ `doing` / `已办`（移入 `done.md` 并留指针）。
> 领活规则见 `docs/protocol/agent-playbook.md`；**第 0 档全部完成前，任何编码类条目不得开工**（`docs/README.md` §4）。

## 第 0 档：文档裁决（当前唯一可做的工作）

| ID | 内容 | 需要谁 | 判据（怎么算完） | 状态 |
|---|---|---|---|---|
| T-001 | 签 Q-01（最低 macOS 14）→ ADR-003 转 accepted | 用户 | **已签 2026-11-16＝macOS 14**；同批签下 ADR-007/008/010 | 已办 |
| T-002 | 签 Q-02（默认热键）→ ADR-010 accepted + `keymap.md` 定稿 | 用户 | 三行默认值无 `待裁决` 标记；`MSSettings` 默认表与之一致 | 已办（11-17 签下 Q-02＝默认热键维持，`ADR-010` accepted；`keymap.md` 已定稿） |
| T-003 | 签 Q-03（9 件工具，含橡皮擦）+ Q-12（D-04 知情确认） | 用户 | `annotate-model.md` §4 表去掉 `待 Q-03`；`requirements.md#FR-ANN-002` 状态转 accepted | 已办（11-17 签下 Q-03＝9 件全进 P0、Q-12＝坚持 D-04；`annotate-model.md` §4 已去标记） |
| T-004 | 签 Q-04（剪贴板表示）+ Q-05（提交动作语义） | 用户 | ADR-014 的实测矩阵填法被认可；`export-clipboard.md` §5 定稿 | 已办（11-17 签下 Q-04＝仅 PNG、Q-05＝四出口且贴出带复制；`ADR-014`/`ADR-011` accepted） |
| T-005 | 签 Q-06（P0 不落盘）+ Q-07（放大镜档位）+ Q-09（跨屏） | 用户 | `vision.md` G-04 与 NFR-005 措辞随之定稿 | 已办（11-17 签下 Q-06＝不落盘不提示、Q-07＝放大镜进 P0、Q-09＝跨屏下一期） |
| T-006 | 签 Q-11（改选区清空标注）+ Q-13（关闭二态）+ Q-10（`.idea/` 入库与否） | 用户 | 同上 | 已办（11-17 签下 Q-11＝清空并提示、Q-13、Q-10＝`.idea/` 不入库） |
| T-007 | 签剩余架构 ADR：**002 / 009 / 011 / 012 / 013 / 014 / 015 / 016**（003/007/008/010 已于 11-16 签下） | 用户 | `docs/adr/README.md` 无 `proposed` 行 | 已办（`adr/README`：accepted 16 / proposed 0，11-17 全签） |
| T-008 | NFR §9 的 4 个取舍确认（回退线 / 键盘不闭环 / VoiceOver / macOS 26） | 用户 | `nfr.md` §9 全部转为决定或降级为 P1 说明 | 已办（11-17 签下：回退线作为触发线、键盘不闭环接受、VoiceOver 与 macOS 26 记 §9） |
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
| T-090 | **自签证书验证**：登录钥匙串建 `MacShot Dev`，在**副本**上签一次，量是否解除 `-3801` 预拒绝与重复弹框；不通过就撤销 | Q-18=A | `scripts/`、`Makefile`、`permissions-tcc.md` | 同一份源码重编两次，第二次采集**不再**返回 `-3801` 且不再弹框 ⇒ 通过；否则撤销证书并如实记 | **done**（E-070 + E-079：授权已勾；重建后产物 sha256 变了而 `permission=granted`、`degenerate=false`；对照实验证明 ad-hoc 那份仍 `-3801` ⇒ 起作用的是 DR=`identifier+certificate leaf`。顺带堵掉 `make build` 把签名打回 ad-hoc 的陷阱） |
| T-091 | **剪贴板只写 PNG**：`MSClipboardWriter` 去掉 TIFF 表示 | Q-04 | `Sources/MSExport/`、`Sources/MSCore/`（协议）、`Sources/MSSettings/`（schema）、`App/`（`MSPNGItem`）、`Tests/MSSettingsTests` | ① 假 pasteboard 只收到**一个 PNG 载荷**且签名是 `89 50 4E 47` ② 真壳 `make probe-clipboard` 读出 `dpi=72×scale` 与 types 集合，并跑 `NSPasteboardItem` 对照组分清"我们写的"与"系统派生的" ③ v1 落盘文件（带已删字段）仍读得回来，热键与目录不回默认 | **done**（E-062；顺带否掉一条不可达的假判据：`NSPasteboard.types` 永远还会有系统派生的 `public.tiff`） |
| T-092 | **「置顶」＝贴出并写剪贴板**：`pin` 语义改造，`copyAndPin` 合并进 `pin` | Q-05 | `Sources/MSSession/`、`Tests/MSSessionTests/PinCommitCopiesTests.swift`、`docs/design/state-machines.md`、`docs/protocol/verification.md` | ① `Enter` 后同时出现贴图与剪贴板 PNG ② `Esc` 仍**不写**剪贴板 ③ `⌘C` 只复制不贴 ④ `ST-001` 行 11/12 与 `V-036` 随之更新 | **done**（E-063；顺带修掉"四个提交出口静默空转"的生产 bug——冻结帧被 `closeOverlay` 提前释放，违反 `ST-001` 行 14） |
| T-093 | **放大镜 + 取色进 P0**（`FR-CAP-016`）：跟随光标的取样窗、像素放大、`C` 复制 Hex、`⇧C` 切格式、`⌥` 强制呼出 | Q-07 | `Sources/MSOverlay/{MSOverlayLoupe.swift,MSOverlayView.swift}`、`Sources/MSSession/`（新事件+新效果）、`Sources/MSCore/MSExternalSeams.swift`（`writeText`）、`Sources/MSExport/`、`App/`、`Tests/{MSOverlayTests,MSOverlayTests/LoupeTests,MSSessionTests/ColorCopyTests}` | ① 放大图中心像素**精确等于**取样色 ② 离屏渲染中心格距取样色 ≤60、距隔壁颜色 >150 ③ `⌥` 出现/收起、拖拽自动出现 ④ 四角落都不出屏 ⑤ `C` 写剪贴板一次且会话不结束、空串不写 ⑥ `⇧C` 只在 Hex/RGB 两档循环 ⑦ `make probe-chrome … loupe` 目视 | **done**（E-068；套件 128 → 137。`W/A/S/D` 按规格不做；真屏幕逐点一致留 `B-036`） |
| T-094 | **工具条图标改 SF Symbols**：按 `design-system.md` §5 的核对表加载；折线箭头自绘 | B-027 | `Sources/MSAnnotate/MSAnnotationIcons.swift`（事实表）、`Sources/MSOverlay/{MSOverlayIcons.swift,MSOverlayView.swift}`、`Sources/MSPin/{MSPinIcons.swift,MSPinWindow.swift}`、`Tests/MSOverlayTests/IconResolutionTests.swift`、`scripts/imgcrop.swift` | ① 11 个工具全部取得到蒙版 ② 未知符号名 = `nil`（回落路径的前提）③ 逐工具量墨：16pt 格子非透明像素 ≥ 14 ④ 尺寸与着色按 `UI-002`（16pt、当前工具 accent、底色 accent @ 16%）⑤ `make probe-chrome` / `make probe-pin` 各目视一次 | **done**（E-064 + E-065；V-050 入册。装载器两份是 `B-031`，收拢要一条开模块的 ADR。`character.cursor.ibeam` 本机渲染成「文」，中文界面正好；换 macOS 版本符号名会漂移 ⇒ ①② 会变红，那是预期的提醒） |
| T-095 | **热键持久化实测**：改绑后重启软件/重启电脑仍在 | Q-02 | `App/MSAppDelegate.swift`（`--probe-hotkey`）、`Makefile`、`docs/architecture/hotkey-and-permissions.md` §3、`docs/protocol/verification.md` | ① 三次独立启动：改绑 → 新进程读盘并注册同一键 → 还原 ② 盘上位置与格式在 `hotkey-and-permissions.md` §3 与 runbook 有出处，并用外部读 JSON 复核 ③ 真按一下新键、重启电脑后仍在 | **done（机制半）**（E-066；③ 两列留人手，登记 `B-032`——与 `B-030` 同一个 TCC 前置，`T-090` 后一起补） |
| T-096 | **焦点还原实测（T-101）**：遮罩关闭后原 app 的前台与输入焦点都回来 | Q-15=A | `spikes/probe-01/`、`overlay-and-selection.md` §2、`V-006` | 四列真值表（激活与否 × 键盘可达 × 前台变化 × **原输入框可否继续输入**）；最后一列不成立就回到 Q-15 重签 | open |
| T-097 | **10 张贴图的内存读数** | Q-12 的安全阀、NFR-005 | `App/`（`--probe-memory`）、`Makefile`、`docs/requirements/nfr.md` 验证列、`done.md` | ① 10 张 4K 源位图的 RSS 增量 vs 330MB ② 单张增量 vs 源×1.5 ③ 关全部贴图后回基线 ±10% ④ 读数必须由外部裁判（`ps`/`footprint`/`vmmap`）复核一次 ⑤ 帧率那半单列 | **未收口**（E-067：`NFR-005` 两条上限都不破——10 张累计 +59.7MB、边际 ≈0.1MB/张 ⇒ Q-12 安全阀未触发；度量口径钉成 RSS/vmmap——`phys_footprint` 看不见 CG 的可回收图像区。**但 `NFR-008` 在两个口径下结论相反（RSS +49% 破线 / footprint +3% 绿），按 §1 第 1 条不自裁 ⇒ `B-035` 等用户定口径**；帧率与重绘成本另留 `B-033`/`B-034`） |
| T-098 | **贴图编辑态撑高窗口**：图片下方长出一条工具带，工具与色板全在带里，画面与导出不被盖、不被缩（B-028 的最终形态，11-17 用户裁决） | B-028（11-17 再裁：撑高，否定折行） | `Sources/MSPin/MSPinWindow.swift`、`Sources/MSAnnotate/MSAnnotationToolbar.swift`、`Tests/MSPinTests/ToolbarFlowTests.swift`、`App/MSAppDelegate.swift`（`--probe-pin`）、`Makefile` | ① `200×140` 撑高后 `imageRect` 仍 140pt、窗口只长高、顶边不动 ② 编辑态导出的位图字节与非编辑态**逐字节相同** ③ 逐格量墨：每个格子与"同尺寸无工具带"渲染相比必须有墨 ④ 最后一行格子用合成鼠标事件点得到 ⑤ `60×40` 预算不够 ⇒ 不撑带、字母仍可用 ⑦ 编辑态 `zoom` 变化后带高 ≤ 图片高、窗口高＝图片×zoom＋带 ⑥ `make probe-pin` 出 `strip=78 image=(0,78,300,200) frame 高 278` + `build/probe-pin.png` 肉眼确认 | **done**（E-061；套件 121/121） |
| T-099 | **会话加"不呈现窗"测试入口**，让端到端判据不弹全屏窗 | B-029（11-17 裁） | `Sources/MSSession/`、`Tests/MSSessionTests/` | ① 走通 `Effect → 分发器 → onToast` 的自动化断言 ② 测试期间屏幕上**不出现**遮罩（这条本身要用日志或窗口计数证明，不能只靠"我觉得没弹"）③ 生产路径行为不变：`make probe-freeze` 仍绿 | **已办**（E-058；顺带抓到 `selectionDidChange` 是空函数这条死线） |
| T-100 | **设置生效与补齐**（11-17 点名）：`appearance`/`showMagnifierWhileDragging` 接上消费者并进窗口，删 `confirmBeforeDiscardingUnexportedPins`（`Q-06` 已裁），补 `FR-SET-002` 承诺的格式/质量/明暗/自启控件 | B-037 | `Sources/MSSettings/`（schema 3）、`Sources/MSOverlay/`、`Sources/MSSession/`、`App/`（设置窗 + `--probe-settings`）、`Tests/MSSessionTests/SettingsTakeEffectTests.swift` | ① 明暗：`.dark` 的 `scrim=0.55`、`.light=0.45`，且同一处画面深色档**量出来更暗**；`.system` ⇒ `window.appearance == nil` ② 放大镜开关：关掉后拖框不自动弹、`⌥` 仍弹，默认档对照必须自动弹 ③ 结构清单证明五组控件与文案都在（`--probe-settings`）④ 开着遮罩改设置当场跟着变（`reapplyChromePreferences`） | **done**（E-071；套件 140 → 142。排版观感与自启注册动作仍需人 ⇒ `B-038`） |
| T-105 | **NFR-008 在 RSS 口径下收口**：区分实验 + 把残留还给系统 | B-035 | `Sources/MSPin/MSPinWindow.swift`（`releaseMemoryIfEmpty`）、`App/MSAppDelegate.swift`（`--probe-memory` 两轮）、`Makefile`、`docs/requirements/nfr.md` | ① 两轮批次峰值差 < 8MB ⇒ 判为缓存不是泄漏 ② 关全部贴图后 RSS 回基线 ±10% ③ 探针里显式再压一次应当变成空操作（产品已压）| **done**（E-072：峰值差 1.2–1.9MB；关闭后 55.1MB vs 基线 58.2MB = −5.1% 绿。`B-034` 重绘成本仍开） |
| T-106 | **需求逐条复审**：`requirements.md` 里还有 32 行状态列是裸 `待裁决`（FR-CAP/SESS/PIN/ANN/EXP/SET 各域都有），它们不是 Q 决策，而是"这条要不要、优先级对不对、验收判据够不够"的逐条旗子 | 用户 | 每条要么转 `已裁`、要么改判 P1/P2、要么明确写"接受现状"；`check-docs.py` 的 P0 计数随之稳定 | **输入已就绪**（E-078：`docs/tasks/review-proposal.md`，32 条逐条给建议档 + 盲区说明）。等你一句"按建议档全刷"或圈改后我再动 `requirements.md` |
| T-107 | **M-6 发布核验起步**：DMG 配方修好并结构可验，已知限制清单成文 | roadmap M-6①④ | `Makefile`（`dmg`/`verify-dmg`）、`scripts/verify-dmg.sh`、`docs/reference/known-limitations.md`、`docs/README.md`、`docs/requirements/nfr.md` §5 | ① `make verify-dmg` 四项全绿（卷根 .app / `/Applications` 软链 / 卷标图标 / DR=identifier+leaf） ② 限制清单每条都有真源 ID，且"还没证完的"一节与 `blocked.md` 对得上 ③ 兼容矩阵每填一格都要带来源与口径 | **部分完成**（E-075：DMG 抓到并修掉三条假陈述；矩阵 1/15 格；M-6①"全新用户流程走一遍"、②矩阵填满、③usage-report 仍开——前三条都要真机或你点头） |
| T-108 | **`make usage-report` 落地 + 日志通道订正** | roadmap M-6③、vision §4 | `scripts/usage-report.sh`、`Makefile`、`Sources/MSSession/`（`commit intent=`）、`Sources/MSPin/`（`edit enter`）、`docs/requirements/vision.md`、`docs/reference/known-limitations.md` | ① `--include-tests` 档能数出非零（模式自校验）② app-only 档在无数据时明确报"不是达标"并退出非零 ③ 四个计数标记都由生产路径发出（跑套件后验证）| **done**（E-076；真实日常数据要等 `T-090` 授权，达标线仍待你裁决） |
| T-109 | **README 使用章节重写**（门面文档过期最害人） | roadmap M-6 交付 | `README.md`、`docs/design/keymap.md` §1 | ① 状态表与实际一致（10 模块 / 142 单测 / M-0…M-4 已落地）② 命令与限制**只引用真源不复制** ③ 键位描述与 `E-063` 之后的出口语义一致（贴出＝带复制）| **done**（E-077；顺手修 keymap §1 两行过期的 `待裁决 Q-02`） |
| T-110 | **用户 11-18 两项改判落地**：① 截图时不要那个自动弹出的放大镜画面 ② 标注要"边画边看到变化" | agent | ① 默认档 `showMagnifierWhileDragging=false`＋schema 3→4，`⌥` 仍可强制；规格五处同步（`FR-CAP-016`/`UI-008`/`keymap.md`/`V-051③`/`README`）＋`charter.md` §6b 记两条改判 ② 遮罩拖拽期草稿实时上屏，判据 `V-053①②③④` ③ 门禁加"默认档代码↔规格同边"并**反证到红** | **done**（E-081；真壳读数 `不按键可见=false / ⌥强制=true / 逐点一致差 6`） |
| T-111 | **用户第二次提同一条**（截图里放大镜还在）⇒ 查清"翻了默认档为什么对他不生效" | agent | ① 真盘 `preferences.json` 的读数与回落路径有判据（`V-054①`，夹具由编码器生成）② 放大镜的拖拽档只认选区拖拽、锚点跟鼠标（`V-054②③`）③ 三条都做过反向验证 ④ `make probe-chrome ARGS=draft` 出一张"标注中途那一帧"给人看 | **done**（E-083；`build/chrome-draft.png` 里红框画着、放大镜没有） |
| T-112 | **工具条"贴出/复制/保存/取消"点了没反应**（用户 11-18 报的第 1 条） | agent | ① 四格各有命中区，点＝按同一个键（`V-055①`）② 窄屏 `showsActions=false` 时格子一起收（`V-055②`）③ `.commit` 的文字与意图一起跟随 `commitBehavior`（`V-055③`）④ 反向验证：格子退回空集 ⇒ 红 | **done**（E-084） |
| T-113 | **改选区不再全清标注**（用户 11-18 报的第 2 条，推翻 `Q-11` 临时默认） | agent | ① 换算走显式函数且与 `canvasPoint` 互为逆运算（`V-056①`）② 屏幕位置实测 <0.6pt（`V-056②`）③ 只清范围外、报数与实际一致（`V-056③`）④ 一条撤销记录（`V-056④`）⑤ 提示改由丢失条数驱动、文案带条数（`V-056⑤`）⑥ 反向验证：换回"全清" ⇒ 三条红 | **done**（E-085；`V-048` 标 superseded、`B-008` 关闭） |
| T-114 | **贴图边缘光晕（悬浮感）**（用户 11-18 要的视觉件） | agent | ① 不吃内容像素（贴边 0.5pt 起密采，`V-057①`）② 由内向外衰减（`V-057②`）③ 导出链零改动（`V-057③`）④ 几何单源 + 工具带长在留白之上（`V-057④`）⑤ 反向验证：拆裁剪＋高光挪进画面 ⇒ ① 红 ⑥ 出图给人看（`make probe-pin` + 双色桌面合成） | **done**（E-086；观感待用户眼睛确认） |
| T-115 | **app 图标去掉底层白色背景**（用户 11-18） | agent | ① 母版四角 alpha=0（`make icon` 自己量，不 0 就退出 1）② icns 读回透明像素 >0 ③ 双色背景合成图目视过一遍 ④ 反向验证：退回 `qlmanage` ⇒ 立刻红 | **done**（E-087；`V-058`） |
| T-116 | ~~热键录制器守卫：拦"仅 `⌘` + 单字母"~~ **撤销**（11-19） | — | — | 前提被 `B-040` 的真根因否定：所有组合都中招，根因是 `register()` 把静态回调擦了，不是键位冲突。要不要给"与系统快捷键撞车"做提示，等 `B-032` 真机回填之后再谈 |
| T-117 | **`blocked.md` 分区核对**：`## 已解` 一节里混着 6 条仍开放的行（`B-031` 需用户签 ADR、`B-032/B-033/B-038` 需用户、`B-034` 需实测、`B-039` 需用户点色值），而开放表里反过来留着已解的 `B-025/B-024/B-008/B-029` 等 | agent | 逐行按"类型"列归位；归完 `grep -c "^| B-"` 总数不减、每条 ID 的引用（`E-0xx`/`V-0xx`/`T-0xx`）仍可解析（`check-docs` ①）；**只搬行不改字**，改字要另开条 | 待办（本次只把 `B-040` 放回开放表） |
| T-118 | **真机回填 `⌃⌘N`**：修完回调擦除后，用户真按一次 `⌃⌘N` 看有没有 `hotkey fired` 与遮罩 | 用户 | ① 日志出现 `hotkey fired id=1 combo=⌃⌘N`（这条只有真按键会打）② 同期 `session hotkey snip` + `t.hotkey→frozen` ③ 旧键（改绑前的组合）不再触发 ④ 重启电脑后仍在 | 待用户（接 `B-032`/`V-037`/`V-059⑤`） |
| T-119 | **保存/导出默认目录改到「下载」**（用户 11-19 改判） | agent | ① 默认值与 schema 5 有判据 ② 迁移认值不认版本：旧默认回落、用户自填不动、v5 显式旧路径尊重 ③ 迁移条件钉死版本号，不许写 `< currentSchemaVersion` ④ `⌘S` 面板与 `⇧⌘S` 共用同一解析点 ⑤ 反证：抽掉迁移只有"旧默认回落"一条红 | **done**（E-090） |
| T-120 | **贴图右键菜单去掉组合键字样**（用户 11-19） | agent | ① 标题精确＝复制/保存/关闭贴图，不含 `⌘/⌥/Esc` ② `keyEquivalent` 仍空串 ③ 动作与选择器一个不少、target 留响应链 ④ 反证：加回 `"  ⌘C"` 立刻红 | **done**（E-091） |
| T-121 | **开机自启实测回填**（`B-041`）：用户勾一次或授权可逆探针，把 `SMAppService` 的真实结果写进台账 | 用户 | ① 日志有 `login item register status=…` ② 注册成功后 `status=enabled` ③ 若抛错，错误文本进 `B-041` 且勾自动退回 ④ 真重启后进程自动起来（这条只能人工，不许推断） | 待用户 |
| T-122 | **权限收缩到功能刚需**（用户 11-19 指令） | agent | ① `make permissions` 绿且能红（塞回全局监听 / 加用途声明两条反证）② 产物 entitlements 实测为空表 ③ 屏幕录制授权在删 `get-task-allow` 后仍有效（真壳读数）④ 遮罩五条出路仍在（`V-055`/`V-043` 那批 + 本地监视器）| **done**（E-093） |
| T-123 | **手动检查更新**（用户 11-19，`ADR-023`） | agent | ① 纯逻辑离线单测 6 条（`V-064`）② `make probe-update` 两支：正常源通过、篡改源必须拒绝且零残留（`V-065`）③ 出网白名单双门禁 ④ 关于面板带作者 | **done**（E-094） |
| T-124 | **一键发布到 GitHub Releases 当更新源**（用户 11-19） | agent + 用户 | ① `--dry-run` 离线跑完（已证）② 仓库地址从 `git remote` 解析，不写死 ③ 真上传后 `--verify-only` 必须绿：远端清单 sha256/bytes 与本地产物一致 + 资产不 404 ④ 没有 gh 也没有 token ⇒ `exit 3` 打印手工两步，不猜 | **待用户**（本机无 `gh`、无 `GITHUB_TOKEN`；`V-066` 的远端那格还空着） |
| T-125 | **发布线纪律**（用户 2026-11-19 裁决：`main` 开发，每次发版自动产生 tag + 发布分支，代码推该分支） | agent | ① `publish-release.sh` 构建前断言 `git status --porcelain` 为空 ② tag/分支名从 plist 版本号推出 ③ 同批创建且指向同一 commit、重复跑幂等、指向别处就 `exit 2` 不覆盖 ④ 脚本不执行 push ⑤ `V-067` + runbook §3c + `AGENTS.md` §3.12 ⑥ 顺带把 `make X` 三处一致做成门禁 | **done**（E-095；远端那一格待 push） |
| T-126 | `done.md` 里 **9 行少一列**（E-073…E-080、E-092：条目与证据之间的竖线在早前某次替换里丢了） | agent | 逐行找到自然边界补竖线（不猜统一位置）、补完整批 `make check` + 目检渲染；同时把 `check-docs.py` 的 `KNOWN_SHORT` 从 9 改小 | 待办（今天查出的既有损伤，不在本次范围，按纪律另登记） |

## 已知"提前做也没用"的项（防顺手实现）

- 窗口/元素自动识别（要动权限策略，P1，ADR-017）。
- 截图历史与 `.macshot` 落盘（Q-06 未定，P1）。
- 图像效果（圆角/阴影/水印）、贴图分组、鼠标穿透（P1/P2）。
- 任何 `CIFilter` 依赖的高斯模糊实现（ADR 未开，先用手写核或推迟）。
