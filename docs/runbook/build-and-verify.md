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
| `make dmg` | `hdiutil create` 打包 `.app`（含 `/Applications` 软链接） | 挂载后能看到 app；`codesign -dv` 显示 `Signature=adhoc` | `hdiutil` 权限 |
| `make install` | 复制到 `/Applications`（或 `~/Applications`），**清除 quarantine 属性** | 复制后 `xattr -l` 无 `com.apple.quarantine`；启动成功 | 目录权限 |
| `make probe-memory` | `open -n` 起一个进程开 10 张 4K 源贴图（随机噪声夹具）→ 逐张读 `phys_footprint` → 关全部再读 → **再开第二批**（批次峰值对比是 `B-035` 的区分实验：不抬升=缓存，抬升=泄漏）；期间用 `ps -o rss` / `footprint` / `vmmap -summary` 外部复核 | 判据看 **RSS 增量**：单张 ≤ 源×1.5、10 张 ≤ 330MB、关完回基线 ±10%（`E-067`）| **别用进程内 `phys_footprint` 当结论**：CG 的图像数据在可回收区，它只报 12MB 而 RSS 报 86MB；夹具也不许用纯色（会被压缩器吃掉，量的是压缩器） |
| `make probe-hotkey` | 三次独立启动：`set`（改绑 ⌥⌘9）→ `show`（读盘并重新注册）→ `restore`（还原 F1）；读数写 `/tmp/macshot-probe-hotkey.txt` | `show` 那行必须是 `读盘=true snip=⌥⌘9 注册=ok`——**下一次进程**仍然认这个键，才算 `V-037④` 的机制半；跑完一定回到 `F1` | 物理按键那半（真按 ⌥⌘9 出遮罩）要人手，见 `B-032`；临时改的是**你的**快捷键 |
| `make probe-clipboard` | 合成图 → `MSClipboardWriter` 真写系统剪贴板 → 读回 `NSPasteboard.types`、PNG 的 `kCGImagePropertyTIFFXResolution`，并用 `NSPasteboardItem` 做对照组 | `types` 里出现 `public.tiff` **不算失败**：对照组证明那是 AppKit 派生的；要绿的是"我们只交一个 PNG 载荷"与 `dpi=72×scale`（`E-062`） | **会覆盖用户剪贴板**，所以不进 `make check`；跑前提醒用户 |
| `make probe-chrome` | 遮罩界面离屏自绘成 `build/chrome.png`；`--dump-chrome <png> loupe` 会合成一次带 `⌥` 的真 `mouseMoved`，把放大镜一起画出来 | 目视用，不判绿；量指定矩形用 `scripts/imgcrop.swift`（`sips -c` 的 `--cropOffset` 在这台机器上被忽略，永远居中裁） | 不碰 TCC，签名/授权怎么变都能跑 |
| `make probe-settings` | `open -n` 真建设置窗，递归打印控件类名与标题到 `/tmp/macshot-probe-settings.txt` | 逐项对上 `FR-SET-002` 的承诺：提交动作、三条热键、目录、命名模板、明暗、放大镜勾选、格式、JPEG 质量、开机自启、权限读数 | **别拿它的 PNG 当眼睛**：这个窗的 label 是 layer-backed，离屏自绘只出轮廓不出文字；排版观感仍需人眼（`B-038`）
| `make probe-pin` | build + `open -n` 起一个真贴窗并立刻进编辑态，把视图离屏自绘成 `build/probe-pin.png`，读数写 `/tmp/macshot-probe-pin.txt` | 读数里 `strip>0` 且 `frame.height == 图片高 + strip`（图片不缩）；PNG 里工具带在画面**下方** | 采集被 TCC 拒（cdhash 换了）时自动退回合成画面——这里裁的是形态不是屏幕内容；`open --args` 对**已运行实例**无效，必须先 `pkill -x MacShot` |
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
4. 清 `build/Derived`（同步文件夹组的纳管列表偶发需要重建）。
5. 记下 Xcode 版本并对照 `adr/ADR-001` 的"风险"条（升级后首次构建要跑全量 `make check`）。

## 4. 实测记录

| 日期 | 目标 | 输出尾行 | 备注 |
|---|---|---|---|
| 2026-11-16 | — | 未执行（裁决期，无工程文件） | M-0 起在此追加，每目标一行 |
