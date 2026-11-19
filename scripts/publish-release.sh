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
retag=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) mode="dry"; shift ;;
    --verify-only) mode="verify"; shift ;;
    --retag) retag=1; shift ;;
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

# 远端有没有这个 ref：git ls-remote --exit-code 用 0=找到 / 2=确认没有 / 其它=查询本身失败。
# 只有"确认没有"才允许挪 ref；查询失败必须当危险处理（宁可停下，也不猜远端是空的）。
remote_has_ref() {
  lr=0
  # 这两个变量只保证一件事：不会卡在"要我输入 GitHub 凭据"上（无 TTY 时那是死路）。
  # 注意它们**不是**上次 rc=128 的原因——`sh -x` 打出真因是 github.com:443 间歇连不上（一次 75s 超时）。
  # 所以失败时必须把 git 的 stderr 原样带出来：`2`=确认没有、`0`=远端已有、其它=真查不到，三者不能混成一个"网络问题"。
  # GIT_TERMINAL_PROMPT/GIT_ASKPASS 只为别卡在要凭据上。别指望强制 HTTP/1.1：
  # 11-19 实测 git 侧 `-c http.version=HTTP/1.1` 四轮全 rc=128（Empty reply / 连不上），比默认更差，
  # 而 curl 侧同一个 URL 加 --http1.1 是稳定拿到判定——两条路不一样，别互相抄。要试就 GIT_HTTP1=1 显式打开。
  ver=""
  [ "${GIT_HTTP1:-}" = "1" ] && ver="-c http.version=HTTP/1.1"
  lr=0
  tries=0
  err=/tmp/macshot-lsremote.err
  while [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    lr=0
    # 变量名不许撞全局：这里曾经用 `out=`，把清单目录 `out="build/release"` 擦成空串，
  # 于是 `rm -f "$out/latest.json"` 变成 `rm -f "/latest.json"`，而 -f 连报错都不给（11-19 实测：包更新了、清单还是 18:05 那份）。
  refs=$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/true git $ver ls-remote --exit-code --$1 origin "$2" 2>"$err") || lr=$?
    if [ "$lr" -eq 0 ]; then
      echo "   （远端已有 $2 —— 一次判定就够，不许挪）"
      return 0
    fi
    if [ "$lr" -eq 2 ]; then
      [ "$tries" -gt 1 ] && echo "   （第 $tries 次查询才拿到判定；本机到 GitHub 的 HTTPS 间歇失败）"
      return 1
    fi
    echo "   （第 $tries 次查询没拿到判定：rc=$lr $(head -1 "$err" | cut -c1-70)）"
    sleep 3
  done
  if [ "$lr" -eq 0 ]; then return 0; fi
  if [ "$lr" -eq 2 ]; then return 1; fi
  echo "✗ 查不到远端有没有 $2：git ls-remote rc=$lr，不敢假定它是空的"
  echo "   git 原话：$(head -2 "$err" | tr '\n' ' ')"
  exit 2
}

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
    if [ "$at" = "$head" ]; then
      echo "→ tag $tag 已存在且就指向当前 HEAD"
    elif [ "$retag" -eq 1 ]; then
      # 挪 tag 的唯一前提：**远端没有这个 tag**。推出去过的 tag 是公开事实，挪它会把别人的下载链接变成谎话；
      # 那种情况只能升版本号重发，所以这里查不到、或查的过程本身失败，一律不挪。
      if remote_has_ref tags "refs/tags/$tag"; then
        echo "✗ 远端已有 $tag ⇒ 那是公开事实，不挪。请升 `Config/Info.plist` 的版本号重发一轮。"; exit 2
      fi
      git tag -f -a "$tag" -m "MacShot $version" "$head"
      echo "→ 已按 --retag 把 $tag 从 $(printf '%.7s' "$at") 挪到 $(printf '%.7s' "$head")（远端无此 tag，且包尚未发布）"
    else
      echo "✗ tag $tag 指向 $(printf '%.7s' "$at")，HEAD 是 $(printf '%.7s' "$head")：两者对不上。"
      echo "   发布前返工 ⇒ 加 --retag（远端确认没有该 tag 才允许挪）；已经发布过 ⇒ 升版本号，不许挪。"
      exit 2
    fi
  else
    git tag -a "$tag" -m "MacShot $version" "$head"
    echo "→ 已打 tag $tag @ $(printf '%.7s' "$head")"
  fi
  if git rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    bhead=$(git rev-parse "$branch")
    if [ "$bhead" = "$head" ]; then
      echo "→ 发布分支 $branch 已存在且就在当前 HEAD"
    elif [ "$retag" -eq 1 ] && ! remote_has_ref heads "$branch"; then
      git branch -f "$branch" "$tag"
      echo "→ 已按 --retag 把发布分支 $branch 挪到 $tag"
    else
      echo "→ 发布分支 $branch 已存在但不在当前 HEAD（不动它：老线上追加提交请手动切过去）"
    fi
  else
    git branch "$branch" "$tag"
    echo "→ 已建发布分支 $branch @ $tag"
  fi
  echo "→ 推送（按纪律由你在终端执行）：git push origin main $tag $branch"
fi

if [ "$mode" != "verify" ]; then
  # 先作废上一轮的清单：这一轮若在写新清单之前被打断（实测被管道 SIGPIPE 打断过一次），
  # 盘上就会留下「新包 + 旧清单」——bytes 还可能恰好相同、sha 完全不同，肉眼看不出来，传上去客户端校验必不过。
  rm -f "$out/latest.json"
  echo "→ 构建 Release 与 DMG"
  make dmg
  [ -f "$dmg" ] || { echo "✗ 没有 $dmg"; exit 1; }
  echo "→ 核验 DMG 结构"
  make verify-dmg
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
  # 配对自检：清单必须描述**此刻盘上这一份包**。上面实测过一次被打断的跑法
  # （`make release-bundle | grep | tail` ⇒ 子 make/hdiutil 收到 SIGPIPE，脚本停在写清单之前，
  #  盘上留着上一轮的过期清单：bytes 恰好相同、sha256 完全不同，肉眼看不出来）。
  # 不查就等于把"客户端下载后校验必不过"留到用户屏幕上才发现。
  now_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
  now_bytes=$(stat -f %z "$dmg")
  m_sha=$(sed -n 's/.*"sha256": *"\([0-9a-f]*\)".*/\1/p' "$out/latest.json" | head -1)
  m_bytes=$(sed -n 's/.*"bytes": *\([0-9]*\).*/\1/p' "$out/latest.json" | head -1)
  if [ "$m_sha" != "$now_sha" ] || [ "$m_bytes" != "$now_bytes" ]; then
    echo "✗ 清单与盘上这份包不对配：清单 \${m_sha%\${m_sha#????????}}…/\$m_bytes 实际 \${now_sha%\${now_sha#????????}}…/\$now_bytes"
    echo "   ⇒ 这一轮没跑完（多半是被管道截断）。重跑：sh scripts/publish-release.sh --dry-run"
    exit 1
  fi
  echo "→ 配对自检 ✔ 清单里的 sha256 与 bytes == 盘上这份包"
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

# ── 取远端：本机 2026-11-19 实测，默认 HTTP/2 拉 GitHub 这个域**稳定 rc=56（接收失败）**，
#    而同一 URL 加 --http1.1 五轮全是 rc=22（＝真的 404）。不降级就会永远报"网络问题"，
#    真原因（还没发布 / 清单不符）根本走不到。所以传输层失败必须降级再试一次。
#    用法：net_get <L|IL> <url>；成功返回 0 并把正文放进 NET_OUT。
NET_RC=0
NET_OUT=""
net_get() {
  NET_RC=0
  NET_OUT=$(curl -fs$1 "$2" 2>/dev/null) || NET_RC=$?
  if [ "$NET_RC" -eq 0 ] || [ "$NET_RC" -eq 22 ]; then return "$NET_RC"; fi
  h1=0
  body=$(curl -fs$1 --http1.1 "$2" 2>/dev/null) || h1=$?
  if [ "$h1" -eq 0 ] || [ "$h1" -eq 22 ]; then
    # 降级只要拿到**判定**（正文或 404）就说明一句：否则读者会把 http1.1 的结论当成 http2 的
    echo "   （HTTP/2 传输失败 rc=$NET_RC ⇒ 降级 --http1.1 后才拿到判定；本机对 GitHub 的 HTTP/2 通道不稳）"
  fi
  if [ "$h1" -eq 0 ]; then
    NET_OUT=$body; NET_RC=0; return 0
  fi
  if [ "$h1" -eq 22 ]; then NET_RC=22; return 22; fi
  NET_RC=$h1; return "$h1"
}

# ── 闭环自检：远端清单能下载、且它写的 sha256 真的等于本地产物 ───────────────
echo "→ 自检远端源：$manifest_url"
# 报错必须分家：curl -f 下 HTTP≥400 是 rc=22（多半"还没发布"），其它 rc 是传输层/DNS/代理故障。
# 实测踩过一次 curl (16) HTTP2 framing 瞬断，旧文案统一写"还没传？"——那会把网络故障误诊成未发布。
if ! net_get L "$manifest_url"; then
  case "$NET_RC" in
    22) echo "✗ 源返回 HTTP 错误（多半是这个 tag/release 还没发布，或勾了 draft/pre-release）：$manifest_url" ;;
    *)  echo "✗ 拉不到清单：curl rc=$NET_RC —— 传输层/DNS/代理问题，**不是「还没发布」的证据**" ;;
  esac
  exit 1
fi
remote=$NET_OUT
remote_sha=$(printf '%s' "$remote" | sed -n 's/.*"sha256": *"\([0-9a-f]*\)".*/\1/p' | head -1)
remote_bytes=$(printf '%s' "$remote" | sed -n 's/.*"bytes": *\([0-9]*\).*/\1/p' | head -1)
remote_version=$(printf '%s' "$remote" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
# 解析失败与源不符是两件事：空值必须当场说"是脚本读不懂"，别让它冒充"清单校验不过"。
case "$remote_sha" in
  ????) ;;
  *) if [ "${#remote_sha}" -ne 64 ]; then
       echo "✗ 脚本从清单里解析不出 sha256（长度=${#remote_sha}）——这是 publish-release.sh 的解析问题，不是源的问题；远端原文前 200 字节："
       printf '%s\n' "$remote" | head -c 200; echo
       exit 1
     fi ;;
esac
if [ -z "$remote_bytes" ] || [ -z "$remote_version" ]; then
  echo "✗ 清单解析不出 bytes 或 version（脚本的问题，不是源的问题）：bytes=$remote_bytes version=$remote_version"
  exit 1
fi
local_sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
local_bytes=$(stat -f %z "$dmg")
[ "$remote_sha" = "$local_sha" ] || { echo "✗ 清单校验和与本地产物不符：远端 $remote_sha 本地 $local_sha"; exit 1; }
[ "$remote_bytes" = "$local_bytes" ] || { echo "✗ 清单字节数与本地不符：远端 $remote_bytes 本地 $local_bytes"; exit 1; }
if ! net_get IL "$asset_url"; then
  case "$NET_RC" in
    22) echo "✗ 资产链接返回 HTTP 错误（多半没传上去，或 release 不是 latest）：$asset_url" ;;
    *)  echo "✗ 探资产失败：curl rc=$NET_RC —— 传输层问题，不是没传的证据：$asset_url" ;;
  esac
  exit 1
fi
echo "✔ 源可用：version=$remote_version sha256 与字节数都对得上，资产可下载"
