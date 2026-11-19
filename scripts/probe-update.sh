#!/bin/sh
# 「检查更新」的端到端判据（V-065），全程 file:// 源、不联网、不碰真 GitHub。
# 两支都要跑：① 正常源 ⇒ 判成 available 且下载校验通过 ② 篡改校验和 ⇒ 必须拒绝并删干净
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app="build/Derived/Build/Products/Debug/MacShot.app"
fake="$root/build/fake-release"
rm -rf "$fake"; mkdir -p "$fake"
cp "$root/build/MacShot-0.1.0.dmg" "$fake/MacShot-9.9.9.dmg" 2>/dev/null || { make dmg >/dev/null; cp "$root/build/MacShot-0.1.0.dmg" "$fake/MacShot-9.9.9.dmg"; }
sha=$(shasum -a 256 "$fake/MacShot-9.9.9.dmg" | awk '{print $1}')
bytes=$(stat -f %z "$fake/MacShot-9.9.9.dmg")

write_manifest() {  # $1=输出  $2=sha256
  printf '{\n  "version": "9.9.9",\n  "notes": "判据用的假版本",\n  "assets": [\n    {\n      "name": "MacShot-9.9.9.dmg",\n      "url": "file://%s/MacShot-9.9.9.dmg",\n      "sha256": "%s",\n      "bytes": %s\n    }\n  ]\n}\n' "$fake" "$2" "$bytes" > "$1"
}

run() {  # $1=清单路径  $2=标签
  rm -f /tmp/macshot-probe-update.txt
  pkill -x MacShot 2>/dev/null || true; sleep 1
  "$app/Contents/MacOS/MacShot" --probe-update "file://$1" >/dev/null 2>&1 &
  p=$!
  i=0; while [ $i -lt 30 ] && ps -p $p >/dev/null 2>&1; do sleep 1; i=$((i+1)); done
  if ps -p $p >/dev/null 2>&1; then echo "   ✗ 探针 30 秒没退出，杀掉"; kill -9 $p 2>/dev/null || true; fi
  echo "── $2"
  sed 's/^/   /' /tmp/macshot-probe-update.txt 2>/dev/null || echo "   ✗ 没出读数"
}

write_manifest "$fake/latest.json" "$sha"
run "$fake/latest.json" "① 正常源（sha256 正确）"
write_manifest "$fake/tampered.json" "$(printf 'deadbeef%s' "${sha:8}")"
run "$fake/tampered.json" "② 篡改源（sha256 被换）——必须拒绝下载且不留文件"
