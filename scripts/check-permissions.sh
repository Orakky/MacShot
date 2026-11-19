#!/bin/sh
# 权限面门禁（V-063）。原则一句话：**功能刚需之外的权限，一条都不许出现**。
# 这个脚本不看文档怎么说，只看代码与产物本身。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
fail=0
note() { printf '   %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; fail=1; }
ok()   { printf '\033[32m✔\033[0m %s\n' "$1"; }

src=$(find "$root/Packages/MacShotKit/Sources" "$root/App" -name '*.swift' 2>/dev/null)

# ① 源码里不许出现的授权面 API（每条都对应一个"我们不该有的权限"）
for pair in \
  "addGlobalMonitorForEvents|全局按键监听 ⇒ 输入监控/辅助功能" \
  "CGEvent.tapCreate|事件 tap ⇒ 输入监控" \
  "AXIsProcessTrusted|辅助功能查询" \
  "requestAccess(for:|相机/麦克风/SCK 授权请求" \
  "NSAppleScript|Apple Events 自动化" \
  ".post(tap:|全局投递事件（只该出现在 /tmp 探针里，不该在产品里）" \
  "CGDisplayStream|连续采集（录屏）" \
  ; do
  key=${pair%%|*}; why=${pair##*|}
  hits=$(printf '%s\n' $src | xargs grep -n "$key" 2>/dev/null | head -3 || true)
  if [ -n "$hits" ]; then
    bad "产品代码里出现 $key —— $why"
    printf '%s\n' "$hits" | sed 's/^/      /' | cut -c1-150
  fi
done
[ $fail -eq 0 ] && ok "源码：没有全局按键监听 / 事件 tap / 辅助功能 / 相机麦克风 / Apple Events / 连续采集"

# ② Info.plist：没有用途声明＝没有多余的申请意图
plist="$root/Config/Info.plist"
usage=$(/usr/libexec/PlistBuddy -c Print "$plist" 2>/dev/null | grep -c "UsageDescription" || true)
if [ "$usage" != "0" ]; then
  bad "Info.plist 里有 $usage 个 NS*UsageDescription —— 每条都是"我要用某个隐私域"的声明，功能不需要就不该写"
else
  ok "Info.plist：零个 NS*UsageDescription（屏幕录制在 macOS 上不需要 plist 声明）"
fi

# ③ 产物 entitlements 必须是空表（get-task-allow 属于调试期权限，不许进发布包）
app="${1:-}"
if [ -n "$app" ] && [ -d "$app" ]; then
  ent=$(/usr/bin/codesign -d --entitlements :- "$app" 2>/dev/null || true)
  for key in get-task-allow app-sandbox temporary-exception network.client personal-information; do
    if printf '%s' "$ent" | grep -q "$key"; then
      bad "签进产物的 entitlements 含 com.apple.security.$key"
    fi
  done
  printf '%s' "$ent" | grep -q "<dict/>" && ok "产物 entitlements：空表（$(basename "$app")）" \
    || { printf '%s' "$ent" | grep -q "<key>" && : || ok "产物 entitlements：没有任何 key"; }
else
  note "（未传 .app 路径 ⇒ 跳过产物侧检查，只查源码与 Info.plist）"
fi

# ④ 系统里实际记了什么：读得到就报，读不到不判红（那是环境，不是缺陷）
db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [ -r "$db" ]; then
  note "TCC 用户库读数：$(sqlite3 "$db" "select service||'='||auth_value from access where client='com.macshot.app';" 2>/dev/null | tr '\n' ' ')"
else
  note "TCC 用户库读不到（需要完全磁盘访问）——不作判据，屏幕录制状态请用 make probe-permission"
fi

[ $fail -eq 0 ] && echo "✔ 权限面通过：刚需只有屏幕录制一项（+ 用户主动勾选的登录项）" || exit 1
