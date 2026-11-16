#!/bin/sh
# 品牌素材注入 .app。真源只有 assets/branding/*.svg；.icns 是 build/ 下的产物（make icon 生成）。
# 往 bundle 里加资源会让 ad-hoc 签名失效 ⇒ 注入后必须重签（D-02）。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-}
[ -n "$app" ] || { echo "用法：sh scripts/inject-brand.sh <MacShot.app>"; exit 2; }
[ -d "$app" ] || { echo "✗ 找不到 bundle：$app"; exit 1; }
[ -f "$root/build/macshot.icns" ] || { echo "✗ 缺 build/macshot.icns，先跑 make icon"; exit 1; }

menubar_svg="$root/assets/branding/macshot-menubar-template.svg"
[ -f "$menubar_svg" ] || { echo "✗ 缺菜单栏图形 $menubar_svg"; exit 1; }

mkdir -p "$app/Contents/Resources"
cp "$root/build/macshot.icns" "$app/Contents/Resources/macshot.icns"
cp "$menubar_svg" "$app/Contents/Resources/macshot-menubar-template.svg"
codesign --force --sign - --timestamp=none "$app" >/dev/null
echo "→ 品牌素材已注入 $app（macshot.icns + macshot-menubar-template.svg，已重签）"
