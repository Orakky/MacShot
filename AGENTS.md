# AGENTS.md — MacShot

macOS 原生截图 → 标注 → 贴图置顶 → 剪贴板 工具（形态参考 Snipaste）。Swift + AppKit，Xcode 工程 + 本地 SPM 多模块包。

## 0. 当前阶段：M-0 已落地，裁决与实现并行（先读这条）

用户 2026-11-16 放行开发：**未签决策按 `docs/charter.md` §6 顶部的临时默认档实现**，不再是"没签就不能写"。现状：

- 已裁决：D-01 首版只做四大件 / D-02 本机签名（11-17 由 ad-hoc 改为**本地自签 `MacShot Dev`**，Q-18=A，理由见 `E-070`） / D-03 Xcode + SPM / D-04 贴图携带可编辑标注层（见 `docs/charter.md` §1）。
- **11-18 两条用户改判（呈现档，不是翻案）**：① 放大镜**默认不自动弹**，只有 `⌥` 强制（`Q-07` 裁的是"要不要做"，这条裁的是"什么时候出现"；偏好 schema 3→4）② 标注**边画边看到**——拖拽期草稿必须实时上屏，判据 `V-053`。两者都记在 §6b 末尾两行，`E-081`。
  **①当天又提了一次**，因为翻默认档对他**不生效**：落盘的 `preferences.json` 里旧默认被 materialize 成 `true` 压过了新默认。三条修复＝迁移（`schema<4` 该字段回落出厂默认）＋范围（放大镜只认**选区**拖拽，画标注不弹）＋锚点跟手，判据 `V-054`、记录 `E-083`。**教训：改"默认值"必须同时改"读旧文件的规则"，否则只对全新用户生效。**
- **11-18 同日再落两条用户改判/缺陷**：③ 工具条"贴出/复制/保存/取消"以前只是画上去的文字、没有命中区（点＝点空白）⇒ `BarAction` + `actionBoxes` 让绘制与命中同一份几何，判据 `V-055`；④ `Q-11` 临时默认"改选区＝全清不可撤销"作废 ⇒ 现档"屏幕位置还在选区里的原地保留、跑出去的才清、一条撤销记录"，判据 `V-056`（`V-048` 标 superseded）。见 §6b 后三行、`E-084`/`E-085`。
- **11-18 又加了一条视觉承诺**：贴图边缘**光晕悬浮感**（`MSPinGlow`：留白 10pt + 三层软环 + 1pt 高光，最后画且奇偶裁剪到留白），`FR-PIN-013` 的 P0 先切一片，开关仍 P1；判据 `V-057`、规格 `UI-003b`、记录 `E-086`。
- **11-19 还有一条文案改判**：贴图右键菜单**不再显示组合键**（`复制 / 保存 / 关闭贴图`，键仍由 `MSPinView.keyDown` 实现，`keyEquivalent` 本来就是空串），判据 `V-061`、记录 `E-091`。
- **11-19 0.1.0 已发布**：远端 `main` / `v0.1.0` tag / `release/v0.1.0` 三条齐，Release 带 `MacShot-0.1.0.dmg` + `latest.json` 两个资产，`make release-bundle ARGS=--verify-only` 绿、真客户端读到 `upToDate`（`E-097`）。**tag 已公开 ⇒ `--retag` 对这轮失效，0.1.x 的修订只能升版本号重发。**
- **11-19 push 授权（用户裁决）**：允许 agent 自行 push（含用 IDE/操控电脑完成发布相关动作），边界见 §3.7——只推自己这轮的 ref，不 force、不删远端 ref。
- **11-19 发布线纪律（用户裁决）**：`main` 保持日常开发；每次发版/升版本都要有 `v<版本号>` tag **和** `release/v<版本号>` 分支，该版本后续修订往对应分支推。名字从 `Config/Info.plist` 的版本号推出，由 `scripts/publish-release.sh` 自动创建，不手写、不代推。判据 `V-067`，路线 `runbook/build-and-verify.md` §3c。
- **11-19 加了「手动检查更新」**（用户指令，`ADR-023`）：只有点菜单「检查更新…」才出网，默认源＝GitHub Releases 的公开 `latest.json`（不用 API ⇒ 免 token、免速率限制）。**`NFR-030` 的"绝不联网"因此改成"唯一出网点是 `App/MSUpdater.swift`"**，`check-style.sh` 与 `check-permissions.sh` 各查一遍（只改一处，另一处会以为还守着）。发布侧 `scripts/publish-release.sh` 最后一步是**回头核对远端清单和本地产物一致**——没跑过这一步之前，"更新源配好了"这句话没有依据。**11-19 已真跑过**：Release v0.1.0 发布后 `--verify-only` 绿、真客户端读到 `upToDate`（`E-097`）。
- **11-19 权限收缩**（用户指令：只留功能刚需）：运行时隐私域**只剩屏幕录制**；摘掉遮罩的全局 `Esc` 监听（要输入监控/辅助功能）、entitlements 清空（删 `get-task-allow`）、`SCShareableContent` 不再枚举桌面窗口；新增 `make permissions` 门禁接进 `check`。条目 `NFR-037`、判据 `V-063`、清单 `permissions-tcc.md` §3c、记录 `E-093`。
- **11-19 两条**：① 热键"注册成功却按了没反应"根因＝`register()` 先 `setHandler` 再 `unregister` 把**静态**回调表擦掉（`E-089`，`V-059`）——我上一轮写进台账的"⌘+单字母冲突"是误诊，已改正；② 保存/导出默认目录按用户改判换成 **`~/Downloads`**（schema 4→5，同批带"认值不认版本"的迁移，`E-090`/`V-060`）。**规矩：改任何默认值，必须同批改"读旧文件的规则"，否则只对全新用户生效。**
- **11-17 已全部裁决**：`docs/adr/README.md` = accepted 16 / proposed 0，`charter.md` §6b 是签字记录；
  §6 那张"临时默认"表只作历史保留，冲突时以 §6b 为准。**还剩两类真口子**：
  ① `requirements.md` 里 32 行状态列是裸 `待裁决`（逐条需求复审，登记为 `T-106`）；
  ② `blocked.md` 里标"需用户"的条目（`B-033/B-034/B-036/B-038` 等，多数卡在同一个 TCC 前置上）。
- 正式代码在 `App/` + `Packages/MacShotKit/` + `MacShot.xcodeproj`（10 模块 + 166 条单测，`make check` 绿）。`stash@{0}` 那份旧骨架已 `apply` 并按 accepted ADR 改写完毕（`modules.md` §12 的 3 处不符都处理了），**不要再 pop 第二次**。

改任何曾被临时默认档覆盖的行为前，先看 §6b 的签字记录（§6 只是历史）；**改判决要用户点头**，agent 不许自己翻案（NFR-036：文档与代码同批提交）。

## 1. 上岗顺序

`docs/charter.md` → `docs/requirements/requirements.md` → `docs/plan/roadmap.md`（取当前 M）→ `docs/tasks/todo.md`（取一个 T）→ 按需读 `docs/architecture/<模块>.md` 与 `docs/design/screens.md`。

## 2. 命令（已生效，与 `docs/runbook/build-and-verify.md` 一致）

```sh
make doctor           # 环境自检：Xcode / SDK / 证书 / 构建号 / 权限 / 未验证项计数
make build            # xcodebuild 无头构建 .app
make test             # swift test（Packages/MacShotKit，无需 Xcode GUI）
make run              # 构建并 open 启动（11-17 起签名身份稳定，重建不再掉授权；旧 Q-18=B 的坑见 E-070）
make run-term         # 构建后直接 exec 产物二进制 —— 日常入口（借终端的屏幕录制授权，不弹框）
make release          # Release 配置构建
make usage-report     # vision §4 的 G-01…G-05 计数（只数 process=MacShot；加 --include-tests 是模式自校验，不是达标数据）
make verify-dmg       # 挂上 DMG 逐条核验：卷根 .app、/Applications 软链、卷标图标、签名身份
make dmg              # 产出 build/MacShot-<version>.dmg（11-17 起用本地自签身份，不再是 ad-hoc）
make install          # 先 make dmg，再装 DMG 里那份 **Release**；覆盖已有安装（去 quarantine）
make contrast         # NFR-024 对比度校验（11 组配对；不达 WCAG 2.2 就退出 1，目前 9/11，见 B-039）
make release-bundle   # 建 tag 与发布分支 + 打包 + 生成 latest.json；--dry-run 不上传，真发布要 gh 或 GITHUB_TOKEN
make probe-update     # file:// 假源跑完整条检查更新，含"篡改校验和必须拒绝"这一支
make permissions      # 权限面门禁（V-063）：源码 / Info.plist / 签进产物的 entitlements 三处一起查
make check            # 本地门禁：build + test + 风格/依赖方向/文档一致性/权限面
make clean            # 清 build 与 Derived
make probe            # 采一帧并打印尺寸/耗时/权限（V-001/V-019 取证）
make probe-permission # 只读屏幕录制授权状态（V-063 的前置读数；不改权限）
make probe-menu       # 打印状态栏菜单行与"权限行是否真挂在菜单上"（常驻读数行的取证）
make probe-chrome     # 遮罩界面离屏自绘成 build/chrome.png（不碰 TCC，用来看）；`loupe` 参数连放大镜一起出图，`draft` 参数按**真落盘偏好**拖一个矩形给你看标注中途那一帧
make probe-clipboard  # 真写系统剪贴板再读回 types/DPI，分清"我们写的"与"系统派生的"（会覆盖剪贴板）
make probe-memory     # 10 张贴图的内存读数（NFR-005/008）：夹具是噪声，读数用 ps/vmmap 外部复核；会短暂开 N 个窗
make probe-hotkey     # 改绑→退出→再启动读回→还原：热键跨进程持久化取证（会临时改你的快捷键，最后还原成 F1）
make probe-toast      # 连发三条 toast：屏上只许剩一个面板、会自己消失、层级压过贴图（V-069）
make probe-settings   # 真建设置窗并打印控件清单 + 每项在窗坐标的 y 范围 + 登录项状态；**控件被裁到窗外就 rc=7**（离屏 PNG 画不出这个窗的文字，判据是清单）
make probe-pin        # 真贴窗 + 编辑态离屏自绘成 build/probe-pin.png，并打印 strip/imageRect 读数（B-028 形态用来看）
make probe-pin-real   # 真截图→真遮罩→真选区→贴出并复制的闭环读数（B-030 的真壳判据；会开遮罩数秒）
make probe-loupe-real # 真采集画面上**按住 ⌥** 开放大镜（11-18 起默认不自动弹），比取样色与渲染中心格，并另记一行"不按键可见="当默认档读数（B-036 的真壳判据；会开遮罩约 12 秒）
make probe-freeze     # 三连拍验冻结语义 + 真剪贴板哨兵（会在你屏幕上开约 3 秒遮罩）
make icon             # assets/branding 的 SVG → build/macshot.icns（AppKit 解 SVG，只用系统工具）；四角不透明就退出 1
make appicon          # build + icon + 注入 .icns 与菜单栏 SVG + 重签（run/run-term/probe/dmg/install/check 都走它）
scripts/reset-tcc.sh   # 重置屏幕录制授权（排查黑图）
```

## 3. 纪律（违反 = 返工）

1. **未观察不写完成。** 说"做完了"必须附判据：命令输出 / 日志行 / 读数 / 截图路径。写不出判据就写"未验证 + 原因"。
2. **一个事实只有一个家。** 需求进 `requirements.md`、决策进 `adr/`、屏幕规格进 `design/screens.md`、待办进 `tasks/todo.md`。别处只写 `见 X#ID`。
3. **`proposed` 的 ADR 不落地为代码**；要动就先补 ADR 并请用户签字。
4. **不改 `MacShot.xcodeproj/project.pbxproj`。** 工程用同步文件夹组，新增源文件放进 `App/` 或 `Packages/MacShotKit/Sources/<Module>/` 即被自动纳管。
5. **模块依赖方向不许反**（`docs/charter.md` §4）。逻辑代码写在包里、能被 `swift test` 覆盖；`App/` 只做组合根与全局装配。
6. **坐标系不许"顺手换算"**（ADR-013）。跨空间换算必须调用显式函数；新换算先写单测。
7. 只用显式路径 `git add <路径>`；提交前 `git status` 复核。`git push` **默认**由用户在终端执行；用户在会话里明确授权时（2026-11-19：「允许自行使用 idea 工具进行 push，可以操控电脑」）agent 可以代推，但只许推**当轮任务自己产生的 ref**（main 上的自己的 commit + 本轮的 tag/发布分支），不许 force、不许删远端 ref、不许碰别人的分支。
8. 交付产物（`build/`、DMG、截图素材、`.idea/`）默认不入库。
9. 遇到与文档矛盾的实现约束 → 记进 `docs/tasks/blocked.md` 并问用户，不自行改设计。
10. 不引入第三方依赖，除非 ADR-015 被 accepted 且写明来源（本机当前**没有 brew**）。

11. **分发器不许 `default:` 空转**（effect/command/intent 的 switch 必须穷举）。2026-11-16 的遮罩卡死事故就是 `default: break` 吞掉了 `closeOverlay`；`check-style.sh` 已拦。全屏模态必须有 ≥2 条退出路径。
12. **发布线：包必须来自 tag 所指的那个 commit**（用户 2026-11-19 裁决）。`main` 日常开发；发版时 `v<版本号>` tag 与 `release/v<版本号>` 分支同批产生，该版本后续修订推该分支。`scripts/publish-release.sh` 先断言 `git status --porcelain` 为空才构建（DMG 不可复现 ⇒ 脏树的包与 tag 对不上，清单里的 sha256 就成了无法核对的空话），再从 plist 推出 tag/分支名并创建。**`git push` 仍由用户在终端执行**（§3.7 不变）。判据 `V-067`，路线 `runbook/build-and-verify.md` §3c。**发布之后不许再构建这一版的包**：`make dmg`/`install`/`release-bundle`（非 `--verify-only`）都会重新压缩换 sha256，而远端清单钉的是发布那一刻的字节 ⇒ 客户端校验必不过；要出新包只能升 `Config/Info.plist` 的版本号重走一轮。

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
