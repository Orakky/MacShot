#!/bin/sh
# `M-6` 准出①的**结构**核验：DMG 挂上以后到底有什么。
# 为什么要脚本而不是"看一眼"：Makefile 的注释以前写着"含 /Applications 软链接"，
# 实测卷根只有 .app——软链从来没有，卷标图标也没有，签名还是 adhoc。注释是假陈述。
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
dmg=$(ls -t "$root"/build/MacShot-*.dmg 2>/dev/null | head -1)
[ -f "$dmg" ] || { echo "✗ 没有 DMG，先 make dmg"; exit 2; }
mp=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mp" "$dmg" >/dev/null || { echo "✗ 挂载失败"; exit 2; }
fail=0
check() { if [ "$2" = 0 ]; then echo "✔ $1"; else echo "✗ $1"; fail=1; fi; }
[ -d "$mp/MacShot.app" ]; check "MacShot.app 在卷根" $?
[ -L "$mp/Applications" ]; check "/Applications 软链（拖拽安装的前提）" $?
[ -f "$mp/.VolumeIcon.icns" ]; check "卷标图标 .VolumeIcon.icns" $?
id=$(codesign -d -r- "$mp/MacShot.app" 2>&1 | grep -o 'designated => .*' | head -1)
case "$id" in
  *certificate\ leaf*) check "签名身份稳定（DR=identifier+leaf，重建不掉授权）" 0 ;;
  *) echo "  DR: $id"; check "签名仍是 ad-hoc（DR=cdhash ⇒ 每次重建都要重新授权）" 1 ;;
esac
ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mp/MacShot.app/Contents/Info.plist" 2>/dev/null)
echo "  版本=$ver  文件=$(du -h "$dmg" | awk '{print $1}')"
hdiutil detach "$mp" >/dev/null 2>&1
[ $fail -eq 0 ] && echo "✔ DMG 结构通过" || echo "✗ DMG 结构有问题"
exit $fail
