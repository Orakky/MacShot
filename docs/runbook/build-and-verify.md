# Runbook：构建、测试与验证

> 本文是 M-0 落地后 `make` 各目标的**规格说明**：现在（裁决期）这些目标还不存在，写在这里是为了 M-0 一次做对、不留口头约定。

## 1. 目标清单与契约

| 目标 | 做什么 | 成功判据（写死在脚本里） | 失败时先查 |
|---|---|---|---|
| `make doctor` | 打印 Xcode/SDK/Swift/系统版本、签名身份数、屏幕录制权限状态、bundle id、构建号、`待实测`/`UNVERIFIED` 计数 | 每项都有值；系统 <14 时**明确拒绝**并说明（ADR-003） | `xcode-select -p`、许可证 |
| `make build` | `xcodebuild -project MacShot.xcodeproj -scheme MacShot -configuration Debug -derivedDataPath build/Derived build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES` | 尾行 `** BUILD SUCCEEDED **`；产物 `build/MacShot.app` 存在且 `CFBundleIdentifier` 正确 | 见 §3 |
| `make test` | `swift test --package-path Packages/MacShotKit` | 全绿；`MSCoreTests`/`MSAnnotateTests`/`MSSessionTests`/`MSSettingsTests` 四个 target 都有用例数（0 视为失败，防空套件） | 包内是否有 UI 依赖泄漏（违反 ADR-012） |
| `make check` | doctor + build + test + 门禁脚本 | §2 全部规则绿 | 具体规则脚本输出 |
| `make run` | build + `open build/MacShot.app`（先杀旧进程） | 菜单栏出现图标且 `log stream` 有 `app.launched`；Dock 无图标（LSUIElement） | 权限、签名变化 |
| `make run-term` | build + 直接 `exec` 产物内的二进制（Q-18 裁定 B 的日常入口） | `log show --info --predicate 'subsystem=="com.macshot.app"'` 出现 `launched`/`capture.backend`/`registered 1 = F1`；采集借**终端**已授予的屏幕录制权限，因此不弹框 | 这条路**证明不了 .app 自身身份可用**（E-033 的坑）；V-021 不能据此标绿 |
| `make release` | Release 配置构建 | 同 build，另加 `strip` 后体积读数（写进 done.md） | 优化导致的编译期差异 |
| `make icon` | `scripts/svg2png.swift` 用 **AppKit 原生 SVG 解码**光栅化 `assets/branding/macshot-icon.svg` → `sips` 缩放 → `iconutil` 打包 | **母版四角 alpha 必须全 0**（脚本自己量，不是 0 就退出 1）；`sips -s format png build/macshot.icns` 读回后透明像素 >0 | 旧版用 `qlmanage`，它把画布刷成**不透明白底** ⇒ app 图标变成白色方块里嵌一个圆角图标（用户 11-18 报的，`E-087`） |
| `make dmg` | `hdiutil create` 打包 **Release** 的 `.app`（含 `/Applications` 软链接＋卷标图标） | `make verify-dmg` 四条全绿；`codesign -dvv` 显示 `Authority=MacShot Dev`（11-17 起；旧判据写的 `Signature=adhoc` 已过期） | `hdiutil` 权限 |
| `make verify-dmg` | `scripts/verify-dmg.sh` 挂上 DMG 逐条核验：卷根有 `.app`、`/Applications` 软链、卷标图标、签名身份 | 四条全绿 | 依赖 `dmg`，会先构建；挂载点残留 ⇒ `hdiutil detach` |
| `make usage-report` | `scripts/usage-report.sh 7d`：只读本地 unified log 统计 G-01…G-05（不联网、不遥测） | 只数 `process=MacShot` 的行 | 空读数＝日志轮转过或没真用过；`--include-tests` 是模式自校验，**不是达标数据** |
| `make contrast` | `xcrun swift scripts/contrast-check.swift`：语义 token 成对算 WCAG 2.2 比值（NFR-024） | 11 组配对全部达线才退出 0 | 目前 9/11，红在 warn 浅档与一个 placeholder（色值候选等你裁 ⇒ `B-039`） |
| `make appicon` | `icon` + `scripts/inject-brand.sh`：把 `.icns` 与菜单栏 SVG 注进产物再重签 | 注入后 `make check` 绿 | 图标四角不透明 ⇒ `make icon` 退出 1；`run/run-term/probe*/dmg/install/check` 都走它 |
| `make permissions` | `scripts/check-permissions.sh`：权限面门禁（`V-063`/`NFR-037`），源码、Info.plist、签进产物的 entitlements 三处一起查 | 越界 API 为零 + 出网只有 `App/MSUpdater.swift` + 产物无 entitlements blob | 没传 `.app` 路径 ⇒ 只查源码侧（会打印跳过）；TCC 用户库读不到不作判据 |
| `make release-bundle` | `scripts/publish-release.sh`：查干净树 → 建 tag 与发布分支 → `dmg` + `verify-dmg` → 生成 `build/release/latest.json` → 上传 → **回头自检远端清单** | `--dry-run` 必须离线跑完并打印 version/bytes/sha256/asset；`--verify-only` 必须绿 | 脏树 ⇒ `exit 2`；本机无 `gh` 又无 `GITHUB_TOKEN` ⇒ `exit 3` 打印手工两步；见 §3c |
| `make install` | **先 `make dmg`，再挂上那个 DMG 用 `ditto` 装**；目标目录＝已有安装所在（`/Applications` 里有就覆盖它，否则 `~/Applications`；`INSTALL_DIR=` 可指定） | ① 复制后 `xattr -l` 无 `com.apple.quarantine` ② 启动成功 ③ **包内与装好的二进制 `shasum -a256` 相等**（11-18 实测：旧写法装的是 **Debug** 产物、和 DMG 里的 Release 从来不是同一个东西，这条一比就露馅） | 目录权限（本机 `/Applications` 属 admin 可写，不需要 sudo） |
| `make probe-memory` | `open -n` 起一个进程开 10 张 4K 源贴图（随机噪声夹具）→ 逐张读 `phys_footprint` → 关全部再读 → **再开第二批**（批次峰值对比是 `B-035` 的区分实验：不抬升=缓存，抬升=泄漏）；期间用 `ps -o rss` / `footprint` / `vmmap -summary` 外部复核 | 判据看 **RSS 增量**：单张 ≤ 源×1.5、10 张 ≤ 330MB、关完回基线 ±10%（`E-067`）| **别用进程内 `phys_footprint` 当结论**：CG 的图像数据在可回收区，它只报 12MB 而 RSS 报 86MB；夹具也不许用纯色（会被压缩器吃掉，量的是压缩器） |
| `make probe-hotkey` | 三次独立启动：`set`（改绑 ⌥⌘9）→ `show`（读盘并重新注册）→ `restore`（还原 F1）；读数写 `/tmp/macshot-probe-hotkey.txt` | `show` 那行必须是 `读盘=true snip=⌥⌘9 注册=ok`——**下一次进程**仍然认这个键，才算 `V-037④` 的机制半；跑完一定回到 `F1` | 物理按键那半（真按 ⌥⌘9 出遮罩）要人手，见 `B-032`；临时改的是**你的**快捷键 |
| `make probe-clipboard` | 合成图 → `MSClipboardWriter` 真写系统剪贴板 → 读回 `NSPasteboard.types`、PNG 的 `kCGImagePropertyTIFFXResolution`，并用 `NSPasteboardItem` 做对照组 | `types` 里出现 `public.tiff` **不算失败**：对照组证明那是 AppKit 派生的；要绿的是"我们只交一个 PNG 载荷"与 `dpi=72×scale`（`E-062`） | **会覆盖用户剪贴板**，所以不进 `make check`；跑前提醒用户 |
| `make probe-chrome` | 遮罩界面离屏自绘成 `build/chrome.png`；`--dump-chrome <png> loupe` 会合成一次带 `⌥` 的真 `mouseMoved`，把放大镜一起画出来 | 目视用，不判绿；量指定矩形用 `scripts/imgcrop.swift`（`sips -c` 的 `--cropOffset` 在这台机器上被忽略，永远居中裁） | 不碰 TCC，签名/授权怎么变都能跑 |
| `make probe-settings` | `open -n` 真建设置窗，递归打印控件类名与标题到 `/tmp/macshot-probe-settings.txt` | 逐项对上 `FR-SET-002` 的承诺：提交动作、三条热键、目录、命名模板、明暗、放大镜勾选、格式、JPEG 质量、开机自启、权限读数 | **别拿它的 PNG 当眼睛**：这个窗的 label 是 layer-backed，离屏自绘只出轮廓不出文字；排版观感仍需人眼（`B-038`）
| `make probe-pin` | build + `open -n` 起一个真贴窗并立刻进编辑态，把视图离屏自绘成 `build/probe-pin.png`，读数写 `/tmp/macshot-probe-pin.txt` | 读数里 `strip>0` 且 `frame.height == 图片高 + strip`（图片不缩）；PNG 里工具带在画面**下方** | 采集被 TCC 拒（cdhash 换了）时自动退回合成画面——这里裁的是形态不是屏幕内容；`open --args` 对**已运行实例**无效，必须先 `pkill -x MacShot` |
| `make probe` | 产物二进制 `--probe-capture`：采一帧并打印尺寸/耗时/权限（`V-001`/`V-019`） | 打印的尺寸与像素一致 | 全黑 ⇒ 查权限，`scripts/reset-tcc.sh` |
| `make probe-permission` | 产物二进制 `--probe-permission`：只读屏幕录制授权状态 | 打印 `screenRecording=granted` | `denied` ⇒ 32 条 P 类判据全部跑不了（`V-063` 的前置） |
| `make probe-menu` | 产物二进制 `--probe-menu`：打印状态栏菜单各行与"权限读数行是否真挂在菜单上" | 菜单里出现 `屏幕录制` 读数行 | 菜单为空＝status item 没建起来 |
| `make probe-pin-real` | 真截图 → 真遮罩 → 真选区 → 贴出并复制的闭环读数（`B-030` 真壳判据） | `/tmp/macshot-probe-pinreal.txt` 四行齐全 | **会在你屏幕上开遮罩数秒**；`pkill -x MacShot` 是它自己做的 |
| `make probe-loupe-real` | 真采集画面上按 `⌥` 开放大镜，比取样色与渲染中心格（`B-036`） | 取样色与中心格一致，另有 `不按键可见=` 当默认档读数 | 11-18 起默认不自动弹 ⇒ 不按 ⌥ 那行才是默认态；开遮罩约 12 秒 |
| `make probe-freeze` | `scripts/probe-freeze.sh`：三连拍验冻结语义 + 真剪贴板哨兵 | 三帧背景一致 + 哨兵未被改 | 会在你屏幕上开约 3 秒遮罩 |
| `make probe-update` | `scripts/probe-update.sh`：`file://` 假源跑完整条检查更新（`V-065`） | ① 正常源 `available` + 落盘 + 本地重算 sha256 与清单一致 ② **篡改源 ⇒ 没有落盘且临时目录文件数 0** | 每轮 20s watchdog（超时 `exit 8`）；并发互锁见 §3b |
| `make clean` | 删 `build/`、`Derived` | — | — |

## 2. 门禁脚本（`scripts/check-*.sh`，ADR-015：自家 grep 代替 lint）

| 脚本 | 规则 | 对应条款 |
|---|---|---|
| `check-style.sh` | 禁 `try!` / `print(` / `as!` / `URLSession`；中文字符只出现在 `MSStrings.swift`；单文件 >400 行报错 | `coding-conventions.md` §4/§9、NFR-030/033 |
| `check-geometry.sh` | `MSCore`/视图宿主层之外出现 `backingScaleFactor`、`Int(CGRect`、`CGRect(width:` 表示像素 → 报警 | ADR-013、NFR-012 |
| `check-deps.sh` | 解析各模块 `import` 与 `modules.md` §11 图比对，反向边即失败（自证：V-029） | ADR-012 |
| `check-docs.sh` | ① P0 行都有大件归属 ② `见 X#ID` 可解析 ③ `adr/README.md` 无 `proposed` 时提示"可编码"；有 `proposed` 且存在代码提交 → 失败（B-001 的机检版） | `docs/README.md` §4、V-031 |
| `contrast-check.swift` | 全部 token 组合 ≥ 4.5:1 | NFR-024、V-026 |
| `v-pixel-align.sh` / `v-perf.sh` | V-002 / V-019 的实拍辅助 | `verification.md` §3 |

`check-docs.sh` 的 ② 特别重要：文档引用一旦解析失败，agent 就会拿旧表述当依据——这是本项目最容易发生的真实故障，所以做成硬门禁而不是提醒。

## 3. 构建失败排查顺序

1. `make doctor` —— 版本/签名/权限基线。
2. `xcodebuild -list -project MacShot.xcodeproj` —— scheme 是否解析到（本地包未被解析时会缺）。
3. 单独 `swift build --package-path Packages/MacShotKit` —— 把"包错"和"工程错"分开。
4. 清 `build/Derived`（同步文件夹组的纳管列表偶发需要重建）。**但 `make install`/`release-bundle` 依赖它**——整目录删掉会让同一条链把整个 App 重建两遍，只想强制重签时删 `MacShot.app/Contents/_CodeSignature` 就够。
5. 记下 Xcode 版本并对照 `adr/ADR-001` 的"风险"条（升级后首次构建要跑全量 `make check`）。

## 3b. 并发与签名互锁（11-19 实测，别再犯）

- 同时跑两个会签名的目标（例：前一个 `make check` 还没结束又起 `make dmg`）⇒ **两个 `codesign` 抢同一个 `build/Derived` 互锁 27 分钟**。现象是"命令挂着不动"，最容易误判成"钥匙串在等用户点授权"。
- 卡住先分清是谁：**`ps -axo pid,etime,command | grep codesign` 有两条以上 ⇒ 是自己撞自己**，`kill` 掉多余的那条即可，不要动钥匙串、也不要当成 TCC 问题去排查。
- **shell 函数里不许复用全局变量名**（11-19 实测咬掉一口）：远端查询 helper 用了 `out=$(git ls-remote …)`，而脚本顶部 `out="build/release"` 是**清单目录**——查询一跑，`out` 就变成 ls-remote 的输出（成功时为空串），于是 `rm -f "$out/latest.json"` 悄悄变成 `rm -f "/latest.json"`，`-f` 连报错都不给，后面 `cat > "$out/latest.json"` 也写到别处。
  取证方式不是读代码而是看**目录 mtime**：`build/release/` 停在 18:04、`latest.json` 停在 18:05，而 DMG 已经是 21:14 那份 ⇒ "这一轮根本没往这个目录写过东西"。改名为 `refs=` 并加注释；同时把两个子 `make` 的 `>/dev/null` 去掉——吞掉输出之后失败只剩一句 `Error 1`，等于让人重新猜一遍。
- **别用管道截断 `make dmg` / `make release-bundle` 的输出**（11-19 实测）：`make release-bundle ARGS=… | grep … | tail -8` 会让子 make 与 `hdiutil` 收到 SIGPIPE，脚本**停在写清单之前**，盘上留下上一轮的过期清单——那次两份文件 bytes 恰好相同（1787336）、sha256 完全不同，肉眼和 `ls` 都看不出来。要截输出就 `> /tmp/x.txt 2>&1` 再读文件。脚本现在写完清单立刻**复算配对**（sha256 与 bytes 两项都从盘上重读比对，不对就 `exit 1`），三条反证：篡改 sha ⇒ 红；只改 bytes（sha 对）⇒ 红；还原 ⇒ 绿。
- 因此 `scripts/probe-update.sh` 这类"启动真 app 再等它打印"的探针**必须带超时**（现为每轮 20s / 全程 90s，`exit 8` 报 watchdog）。上一版没有，挂住的时候屏幕日志是空的，看起来完全像"还在跑"。

## 3c. 发布一个版本的完整一轮（git 路线，用户 2026-11-19 裁决）

**规则**：`main` 是唯一日常开发线；每次发版产生**一个 tag + 一个发布分支**，该版本的后续修订往发布分支推。两者的名字都从 `Config/Info.plist` 的版本号推出（`v<版本>` 与 `release/v<版本>`），**不手写**——手写就会和 plist 分家，而 `MSUpdate.decide` 只认 plist 里那个数字。

| 步 | 动作 | 断言 / 为什么 |
|---|---|---|
| 1 | 改 `Config/Info.plist` 的 `CFBundleShortVersionString` + `CFBundleVersion`，**单独一个 commit** | 不动版本号 ⇒ 检查更新永远 `upToDate`；同号 release 的资产还会互相覆盖 |
| 2 | `git status --short` 必须为空 | 包里的代码 == HEAD。脏树打的包，tag 就在说谎 |
| 3 | `make release-bundle ARGS=--dry-run` | 脚本自己再查一遍干净树（不干净 `exit 2`，不硬来）→ 建 `v<版本>` tag → 建 `release/v<版本>` 分支 → `make dmg` + `verify-dmg` → 生成**与包配对**的清单。之后**不要再 rebuild**：DMG 压缩不可复现，重建就换 sha256 |
| 4 | `git push origin main v<版本> release/v<版本>` | **由你在终端执行**（`AGENTS.md` §3.7）；脚本只打印这一行，绝不代推 |
| 5 | 网页 releases/new 选**已有** tag，上传 `build/MacShot-<版本>.dmg` 与 `build/release/latest.json` | 两个都要传（客户端按固定名 `latest.json` 取清单）；**不勾 Draft、不勾 Pre-release** ⇒ `/releases/latest/download/` 只解析非草稿非预发布，勾了客户端就永远 404 |
| 6 | `make release-bundle ARGS=--verify-only` | 拉远端清单，`sha256`/`bytes` 与本地重算逐字段比对，再 `curl -I` 确认资产不是 404。**这一步绿之前"源配好了"没有依据**（`V-066`/`V-067`） |

**git 侧的连通性另一回事（11-19 实测，别把两边的结论互相抄）**：同一时刻 `curl` 加 `--http1.1` 对同一个 URL **稳定**拿到判定（五轮全 `rc=22`），
而 `git ls-remote` 默认走 HTTP/2 时**七次里只有 1 次**拿到判定（`rc=128`：Failed to connect / `RPC failed; curl 16 Error in the HTTP2 framing layer`），
强制 `-c http.version=HTTP/1.1` 反而**四轮全 `rc=128`**（Empty reply from server）⇒ **对 git 不许默认降版本**（`GIT_HTTP1=1` 才打开），
改成**重试三次**：任何一次 `rc=0`（远端已有该 ref）立刻停下不挪，`rc=2` 才算"确认没有"，三次都没判定就明说"查不到、不挪"。
挪 tag 这件事的权限全押在这三档上，所以宁可停下来让人重跑，也不许把"网络没通"当成"远端是空的"。

**半途跑不许留下会说谎的清单**：`--dry-run` 一开工就先 `rm -f build/release/latest.json`，再构建、再写清单、再复算配对。
不删的话，被 SIGPIPE 打断的那一轮就是「新包 + 上一轮的旧清单」——实测两份包 bytes 只差 1、sha 完全不同，`ls -la` 看不出来。

**自检的传输层坑（11-19 实测）**：本机 `curl -fsL https://github.com/...:443` 走默认 HTTP/2 **稳定 rc=56（接收失败）**，同一 URL 加 `--http1.1` 才是真的 `rc=22`（404，因为还没发布）。所以 `publish-release.sh` 的自检是"默认试一次，非 22 就降级 `--http1.1` 再试"，并且**降级只要拿到判定就打印一行**——否则读者会把 http1.1 的结论当成 http2 的。报错也分家：`22` 说"多半还没发布/勾了 draft"，其它 rc 说"传输层问题，不是没发布的证据"。
| 7 | `docs/tasks/done.md` 补一条 E：版本号、tag、commit、第 6 步读数 | 未观察不写完成 |

**老线热修**：切到 `release/v0.1.x` 改，版本升到 `0.1.2`，同批产生 `v0.1.2` + `release/v0.1.2`。注意 GitHub 的 `latest` 别名按**创建时间**解析、不按版本号：发一个更老版本号的热修会把 `latest` 抢过去。客户端 `decide` 是 `latest <= now ⇒ upToDate`，**不会误降级安装**，但新版本用户会看不到真正最新的清单——所以热修也要把版本号往上抬。

**重复跑是幂等的**：tag/分支已存在且就指向 HEAD ⇒ 只报"已存在"。

**发布前返工**（tag 已经打好了、但还得再改一版代码/文档）：`make release-bundle ARGS="--dry-run --retag"`。它先把包与清单重算一遍，再把 `v<版本>` 与 `release/v<版本>` 一起挪到新 HEAD——**挪之前必须 `git ls-remote` 确认远端没有这个 tag**，查询失败也算危险、一律不挪。已经发布过就**不许**再挪：那会让别人手里已下载的链接与清单指向不同代码，只能升版本号重发一轮（`V-067` ③）。

## 4. 实测记录

| 日期 | 目标 | 输出尾行 | 备注 |
|---|---|---|---|
| 2026-11-16 | — | 未执行（裁决期，无工程文件） | M-0 起在此追加，每目标一行 |
