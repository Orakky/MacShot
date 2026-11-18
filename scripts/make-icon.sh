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

master="$work/macshot-icon-1024.png"
swift "$root/scripts/svg2png.swift" "$src" "$master" 1024 >/dev/null || { echo "✗ SVG 光栅化失败"; exit 1; }
png="$master"
[ -f "$png" ] || { echo "✗ 没产出母版 $png"; exit 1; }
# 白底回归检查：四角必须透明。qlmanage 当年就是把画布刷成不透明白底，
# 于是 app 图标变成"白色方块里嵌一个圆角图标"（用户 11-18 报的）。
corners=$(swift -e '
import CoreGraphics
import ImageIO
import Foundation
let p = CommandLine.arguments[1]
guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(s, 0, nil) else { print("read-fail"); exit(0) }
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
print(pts.map { String(px[($0.1 * w + $0.0) * 4 + 3]) }.joined(separator: ","))
' "$png" 2>/dev/null)
case "$corners" in
  *read-fail*|"") echo "✗ 读不到母版像素，无法判定白底"; exit 1 ;;
esac
if [ "$corners" != "0,0,0,0" ]; then
  echo "✗ 母版四角不透明（alpha=$corners）⇒ 白底回来了，图标会是白色方块"
  exit 1
fi
echo "→ 母版 $(basename "$png") $(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixel/{printf "%s ", $2}') 四角 alpha=$corners（透明＝无白底）"

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
