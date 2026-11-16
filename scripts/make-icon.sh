#!/bin/sh
# SVG → .icns。真源只有 assets/branding/macshot-icon.svg 一个；产物全落 build/，不入库。
# 只用系统工具（qlmanage 光栅化 / sips 缩放 / iconutil 打包），不引第三方 —— ADR-015。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/assets/branding/macshot-icon.svg"
work="$root/build/icon.work"
iconset="$work/macshot.iconset"
out="$root/build/macshot.icns"

[ -f "$src" ] || { echo "✗ 找不到真源 $src"; exit 1; }
rm -rf "$work"
mkdir -p "$iconset"

qlmanage -t -s 1024 -o "$work" "$src" >/dev/null 2>&1 || true
png=$(find "$work" -maxdepth 1 -name '*.png' -print)
n=$(printf '%s' "$png" | grep -c . || true)
[ "$n" = 1 ] || { echo "✗ qlmanage 应产出 1 张母版 PNG，实际 $n 张（QuickLook 不可用？）"; exit 1; }
echo "→ 母版 $(basename "$png") $(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixel/{printf "%s ", $2}')"

gen() { sips -Z "$2" "$png" --out "$iconset/$1" >/dev/null; }
gen icon_16x16.png    16
gen icon_16x16@2x.png 32
gen icon_32x32.png    32
gen icon_32x32@2x.png 64
gen icon_128x128.png  128
gen icon_128x128@2x.png 256
gen icon_256x256.png  256
gen icon_256x256@2x.png 512
gen icon_512x512.png  512
gen icon_512x512@2x.png 1024

iconutil -c icns "$iconset" -o "$out"
echo "→ $out（$(du -h "$out" | cut -f1 | tr -d ' ')，最大层 $(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}')px）"
