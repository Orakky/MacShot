#!/bin/sh
# 一键打包 + 发布到 GitHub Releases，作为「检查更新」的软件源（ADR-023 / FR-UPD-004）。
#
# 为什么要有这个脚本：客户端能查更新的前提是**有个可查的源**。源不是"随便放个文件"，
# 它必须满足客户端的两条硬要求：① 清单里的 url 真的能下载 ② sha256 与下载到的字节一致。
# 所以脚本最后一步是**回头自检这两条**，不是"上传完就宣称成功"。
#
# 用法：
#   sh scripts/publish-release.sh --dry-run          # 建 tag/发布分支 + 打包 + 自检，不上传（本机默认走这条）
#   sh scripts/publish-release.sh -m "更新说明"       # 有 gh 或 GITHUB_TOKEN 时才真上传
#   sh scripts/publish-release.sh --verify-only      # 只验远端 latest.json 与本地产物是否一致
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist)
dmg="build/MacShot-$version.dmg"
out="build/release"
notes="MacShot $version"
mode="publish"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) mode="dry"; shift ;;
    --verify-only) mode="verify"; shift ;;
    -m) notes="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 2 ;;
  esac
done

# 仓库地址从 git remote 取，不写死：写死的那份会和真实仓库分家（本项目已经吃过一次"两处各写一遍"的亏）
remote=$(git config --get remote.origin.url 2>/dev/null || true)
# BSD sed 不认 `??`（第一版就是被它咬了：sed 报错但赋值仍"成功"，repo 变成空串）
repo=$(printf '%s' "$remote" | sed -E 's#^(https://|git@)github\.com[:/]##; s#\.git$##')
case "$repo" in */*) ;; *) echo "✗ 解析不出 owner/repo（remote=\"$remote\"）；GitHub Releases 源需要它"; exit 2 ;; esac
tag="v$version"
asset_url="https://github.com/$repo/releases/download/$tag/MacShot-$version.dmg"
manifest_url="https://github.com/$repo/releases/latest/download/latest.json"

branch="release/v$version"

# ── 发布线（AGENTS.md §3.12 / V-067）：tag 与 release 分支都从 plist 的版本号推出来 ──
# 为什么先卡干净树：DMG 不是逐字节可复现的，"这个包里是哪一版代码"唯一的凭据就是 tag→commit。
# 脏树打出来的包，清单里的 sha256 就成了无法核对的空话，所以宁可不动。
if [ "$mode" != "verify" ]; then
  dirty=$(git status --porcelain 2>/dev/null || true)
  [ -z "$dirty" ] || { printf '✗ 工作树不干净：包与 tag 会对不上。先提交或还原这些改动：\n%s\n' "$dirty"; exit 2; }
  head=$(git rev-parse HEAD)
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    at=$(git rev-list -n 1 "$tag")
    [ "$at" = "$head" ] || { echo "✗ tag $tag 已存在但指向 $(printf '%.7s' "$at")，HEAD 是 $(printf '%.7s' "$head")；不猜哪个算数"; exit 2; }
    echo "→ tag $tag 已存在且就指向当前 HEAD"
  else
    git tag -a "$tag" -m "MacShot $version" "$head"
    echo "→ 已打 tag $tag @ $(printf '%.7s' "$head")"
  fi
  if git rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    echo "→ 发布分支 $branch 已存在（不重置它：老线上追加提交请手动切过去）"
  else
    git branch "$branch" "$tag"
    echo "→ 已建发布分支 $branch @ $tag"
  fi
  echo "→ 推送（按纪律由你在终端执行）：git push origin main $tag $branch"
fi

if [ "$mode" != "verify" ]; then
  echo "→ 构建 Release 与 DMG"
  make dmg >/dev/null
  [ -f "$dmg" ] || { echo "✗ 没有 $dmg"; exit 1; }
  echo "→ 核验 DMG 结构"
  make verify-dmg >/dev/null
  sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
  bytes=$(stat -f %z "$dmg")
  mkdir -p "$out"
  printf '%s  %s\n' "$sha" "MacShot-$version.dmg" > "$out/MacShot-$version.dmg.sha256"
  cat > "$out/latest.json" <<EOF
{
  "version": "$version",
  "notes": "$notes",
  "assets": [
    {
      "name": "MacShot-$version.dmg",
      "url": "$asset_url",
      "sha256": "$sha",
      "bytes": $bytes
    }
  ]
}
EOF
  echo "→ 清单 $out/latest.json"
  echo "   version=$version bytes=$bytes sha256=${sha%"${sha#????????}"}…"
  echo "   asset=$asset_url"
fi

if [ "$mode" = "dry" ]; then
  echo "→ dry-run：不上传。产物在 $out/，可手动拖进 https://github.com/$repo/releases/new（tag $tag）"
  echo "   要上传的资产：$dmg 与 $out/latest.json（两个都要，客户端只认 latest.json）"
  exit 0
fi

# ── 上传：三条路，按本机有什么挑 ─────────────────────────────────────────────
if [ "$mode" = "publish" ]; then
  if command -v gh >/dev/null 2>&1; then
    echo "→ 用 gh 发布"
    gh release view "$tag" --repo "$repo" >/dev/null 2>&1 \
      || gh release create "$tag" --repo "$repo" --title "MacShot $version" --notes "$notes"
    gh release upload "$tag" "$dmg" "$out/latest.json" --repo "$repo" --clobber
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "→ 用 GITHUB_TOKEN + curl 发布（token 不回显）"
    api="https://api.github.com/repos/$repo/releases"
    body=$(printf '{"tag_name":"%s","name":"MacShot %s","body":"%s","draft":false,"prerelease":false}' "$tag" "$version" "$notes")
    id=$(curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
         -d "$body" "$api" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
    [ -n "$id" ] || { echo "✗ 建 release 失败（tag 可能已存在，改用 gh release upload）"; exit 1; }
    curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" \
      --data-binary "@$dmg" "https://uploads.github.com/repos/$repo/releases/$id/assets?name=MacShot-$version.dmg" >/dev/null
    curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" -H "Content-Type: application/json" \
      --data-binary "@$out/latest.json" "https://uploads.github.com/repos/$repo/releases/$id/assets?name=latest.json" >/dev/null
  else
    echo "✗ 本机没有 gh，也没设 GITHUB_TOKEN ⇒ 不猜、不硬试。"
    echo "   手工两步（文件都已备好）："
    echo "   1) https://github.com/$repo/releases/new 建 tag $tag，标题 MacShot $version"
    echo "   2) 上传 $dmg 与 $out/latest.json"
    echo "   传完再跑：sh scripts/publish-release.sh --verify-only"
    exit 3
  fi
fi

# ── 闭环自检：远端清单能下载、且它写的 sha256 真的等于本地产物 ───────────────
echo "→ 自检远端源：$manifest_url"
remote=$(curl -fsSL "$manifest_url") || { echo "✗ 拉不到 latest.json（还没传？CDN 缓存？）"; exit 1; }
remote_sha=$(printf '%s' "$remote" | sed -n 's/.*"sha256":"\([0-9a-f]*\)".*/\1/p' | head -1)
remote_bytes=$(printf '%s' "$remote" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p' | head -1)
local_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
local_bytes=$(stat -f %z "$dmg")
[ "$remote_sha" = "$local_sha" ] || { echo "✗ 清单校验和与本地产物不符：远端 $remote_sha 本地 $local_sha"; exit 1; }
[ "$remote_bytes" = "$local_bytes" ] || { echo "✗ 清单字节数与本地不符：远端 $remote_bytes 本地 $local_bytes"; exit 1; }
curl -fsIL "$asset_url" >/dev/null || { echo "✗ 资产链接还 404：$asset_url"; exit 1; }
echo "✔ 源可用：version=$(printf '%s' "$remote" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1) sha256 与字节数都对得上，资产可下载"
