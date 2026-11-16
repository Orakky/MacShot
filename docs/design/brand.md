# 品牌图形（真源）

> 真源：定稿图形、各文件的用途边界、运行时装载方式与取证结论。代码与产物只引用本文，别处不再复述图形规格。
> 状态：**已定稿 C4「冻结帧取出」**（定稿过程与落选稿存档见提交 `2c6c9c4`，对照页 `assets/branding/contact-sheet.html`）。

## 1. 文件清单（谁是真源，谁是产物）

| 路径 | 用途 | 地位 |
|---|---|---|
| `assets/branding/macshot-icon.svg` | 方形主图标（Finder/关于面板/DMG） | **真源** |
| `assets/branding/macshot-menubar-template.svg` | 菜单栏单色图形（LSUIElement 没有 Dock 图标，这是唯一的常驻可见面） | **真源** |
| `assets/branding/macshot-icon-mono-{dark,light}.svg` | 单色场景（深浅底各一） | 真源 |
| `assets/branding/macshot-icon-square-avatar.svg` | 圆角方形头像位（社交/文档） | 真源 |
| `assets/branding/macshot-lockup-{horizontal,vertical}.svg` | 图形 + 字标组合 | 真源 |
| `assets/branding/concepts/c{1,2,3}-*.svg` | 落选三稿 | 存档，不再引用 |
| `build/macshot.icns`、`build/icon.work/` | `.icns` 与其间帧 | **产物**，已 gitignore，不入库 |

色值只取 `design-system.md` §2 的 token；§9 禁的渐变/投影不在图形里用（C4 原稿的"洞"用墨色会读成投影，改深蓝凹陷）。

## 2. 运行时装载（实测，不是推断）

| 项 | 结论 | 判据 |
|---|---|---|
| SVG 是否需要先光栅化 | **不需要**。AppKit 直接把 SVG 当矢量资源用，所以图形只有一份真源，不存在要同步的 PNG 副本 | 探针：`NSImage(contentsOf: …svg)` → `size=(24,24)`、重画 18×18 后 `inkCoverage=0.346`（非空） |
| 菜单栏尺寸 | 18pt 见方，`isTemplate = true`（深浅菜单栏由系统着色） | `MSStatusGlyph.pointSize`；实跑日志 `status glyph=18.0pt template ink=0.31` |
| 素材缺席怎么办 | 回落文字 `✂` 并**记 error 日志**，入口不许消失（FR-HOT-013） | `StatusGlyphTests.missingAssetReturnsNil` |
| 真机可见性 | 实拍菜单栏：描边屏幕 + 右上角实心小块，模板着色生效；未启动/已启动两张图差异区 **18px 高**，与图形点高一致 | `screencapture -x -R0,0,1600,26` 前后对照 + `/tmp/imgdiff`（changed=2950，bbox 高 18） |

> "空白模板图"在系统菜单栏里长得和"图标丢了"一模一样，所以 `inkCoverage` 是被断言的量，不是调试用的临时数字。

## 3. 管线

```
make icon      → scripts/make-icon.sh   qlmanage 光栅 1024 母版 → sips 十档 → iconutil 出 build/macshot.icns
make appicon   → build + icon + scripts/inject-brand.sh <app>   注入 .icns 与菜单栏 SVG，然后重签（加资源会让 ad-hoc 签名失效，D-02）
```

`run / run-term / probe / probe-permission / dmg / install / check` 都走 `appicon`：入口不许跑在缺素材的 bundle 上。只用系统工具，不引第三方（ADR-015）。

## 4. 未决 / 未做

1. **About 面板与 DMG 卷标视觉**未过目（`CFBundleIconFile` 已生效，但关于面板长什么样没实拍）。
2. `.icns` 的**暗底/亮底自适应**没做（macOS 15 会自动加圆角与着色，实拍后再判要不要出分层版）。
3. 应用内**深色图标变体**（`mono-dark`）目前无人引用——等设置窗或贴图边框用到再说，不提前接线。
