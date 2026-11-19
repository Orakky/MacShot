# ADR-023：手动检查更新 + GitHub Releases 作为软件源

状态：**accepted**（2026-11-19 用户指令，原话见「决定」段）
关联：`FR-UPD-001`、`NFR-030`（本 ADR 修订它）、`ADR-015`（零第三方依赖）、`ADR-004`（非沙盒）、`V-064`/`V-065`/`V-066`

## 背景

`NFR-030` 与 `requirements.md` §5 原本写着"不联网、无遥测、无更新检查、不做更新弹窗"。
用户 2026-11-19 明确要求两件事：

> **新增检查更新的功能，不需要自动检查更新，让用户手动点击 检查更新，并允许服务可以在检查完更新后让用户自行选择是否需要更新软件**
> **检查更新的前提是：需要有对应的软件源，因此需要构建可以一键打包的脚本，允许将产物 release 推送至 github 的 release 上作为后续的更新的软件源**

约束：本机没有 brew、没有 `gh`（实测 `command -v gh` 为空）；签名是本地自签 `MacShot Dev`（`ADR-004`/`T-090`），
**没有** Developer ID 证书，也没有公证。仓库远端是 `https://github.com/Orakky/MacShot.git`。

## 决定

1. **只有手动**。入口是状态栏菜单「检查更新…」。没有启动检查、没有定时器、没有后台轮询——
   这条是整份 ADR 的核心取舍，`check-style.sh` 用"出网只许出现在 `App/MSUpdater.swift`"把它变成机器约束。
2. **源 = GitHub Releases 的公开下载路径**，不用 REST API：
   `https://github.com/Orakky/MacShot/releases/latest/download/latest.json`。
   免 token、免速率限制、免把仓库名拼进查询参数。清单形状（`MSCore.MSUpdateManifest`）：
   `version` / `notes` / `assets[{name,url,sha256,bytes}]`，字段缺一个就解码失败，不猜默认值。
3. **用户自己选**。有新版才弹面板，三个出口：`下载更新包` / `复制下载链接` / `稍后`。
   面板里先写清版本、大小、SHA-256 前缀、落地目录，再让人决定。
4. **下载必须校验才交系统**。落到导出默认目录（`~/Downloads`，与保存截图同一个地方，不另开设置项），
   分块算 SHA-256 与清单比对，**字节数也对得上**才 `NSWorkspace.open` 挂载；
   不一致就删文件、报错、不挂载。
5. **一键发布脚本** `scripts/publish-release.sh`：`make dmg` → `make verify-dmg` → 算 sha256/bytes →
   生成 `build/release/latest.json` → 上传（有 `gh` 用 `gh`；否则有 `GITHUB_TOKEN` 用 curl；
   两者都没有就打印手工两步并退出 3，**不猜、不硬试**）。仓库地址从 `git remote` 解析，不写死。
   最后一步是**闭环自检**：拉远端 `latest.json`，比对本地产物的 sha256 与字节数，再 `curl -I` 资产链接。
   没做这一步之前，"源配好了"这句话没有任何依据。
6. **纯逻辑进包**：版本比较与清单解码在 `MSCore`（`MSVersion` / `MSUpdateManifest`），
   可离线单测（`V-064`）；网络与 UI 只在 App 层（`V-065` 的探针用 `file://` 源跑完整条链）。

## 后果

- `NFR-030` 从"不联网"改成"**只有手动检查更新这一条出网路径**"；遥测、统计、自动更新仍然禁止，
  且由门禁与 `check-permissions.sh` 的出网点白名单一起守。
- 版本号比较必须逐段比数字：`0.10.0 > 0.9.0`，比字符串会判反（`UpdateCoreTests` 钉住）。
- 面板是新增界面，规格落 `screens.md#UI-010`；不做更新弹窗、不做"发现新版自动提示"。

## 完整性的诚实边界（不许 overclaim）

- SHA-256 + HTTPS 证明的是**传输没被改、清单与文件对得上**；
  **它不证明作者是本人**——本产物用本地自签证书（`ADR-004`），别人的机器上 Gatekeeper 不认，
  下载后首次打开需要用户自己承担"这是作者自签的包"这件事。
- 要真正可验证的作者身份，需要 Apple Developer ID 签名 + 公证（notarization），
  那是**另一条 ADR + 一笔付费账号**的决定，本 ADR 不假装已经做到。
- 源被换/被劫持的防线目前只有 HTTPS 与清单校验和；若将来加签名清单（minisign 之类）需引第三方工具，
  与 `ADR-015` 冲突，要单独裁决。

## 回退

把「检查更新…」菜单项与 `App/MSUpdater.swift` 删掉即可完全退出网络面；`MSCore` 里的纯逻辑无害。
自建源：设 `MACSHOT_UPDATE_URL` 指向任意 `latest.json`（判据与内测都靠这个口子）。
