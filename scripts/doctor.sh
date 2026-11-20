#!/bin/sh
# 环境自检（docs/runbook/build-and-verify.md §1）。任何一项不满足就退出非零。
set -e
fail=0
note() { printf '%-26s %s\n' "$1" "$2"; }
need() {
  if [ -z "$2" ]; then echo "✗ $1 缺失"; fail=1; else note "$1" "$2"; fi
}

need "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
need "arch" "$(uname -m)"
need "Xcode" "$(xcodebuild -version 2>/dev/null | head -1)"
need "Swift" "$(swift --version 2>/dev/null | head -1)"
need "SDK (macosx)" "$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"
need "bundle id" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Config/Info.plist 2>/dev/null)"
need "version" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist 2>/dev/null)+$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Config/Info.plist 2>/dev/null)"
need "LSMinimumSystemVersion" "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Config/Info.plist 2>/dev/null)"

ids=$(security find-identity -v -p codesigning 2>/dev/null | grep -c '"' || true)
note "codesign identities" "$ids (>0 表示可走 Developer ID；0 则只能 ad-hoc，见 ADR-004)"
note "brew" "$(command -v brew >/dev/null && echo present || echo absent '（ADR-015 预期：不依赖）')"

# 未验证项计数：代码里标 UNVERIFIED 的地方 + 文档里仍写「待实测」的条目
unv=$(grep -rn "UNVERIFIED" App Packages 2>/dev/null | wc -l | tr -d ' ')
tbd=$(grep -rn "待实测" docs 2>/dev/null | wc -l | tr -d ' ')
note "代码内 UNVERIFIED" "$unv"
note "文档内 待实测" "$tbd"

# 只数**状态列**：以前这里是 grep -c "proposed"，把表头说明文字里那句"状态 proposed 不得落地"也算进去，
# 于是 16 条全签完之后仍然打印"proposed 4"——一个假红灯，读的人只能猜（11-20 实测）。
proposed=$(grep -cE '^\| ADR-[0-9]+.*\*\*proposed\*\*' docs/adr/README.md || true)
note "ADR proposed" "$proposed（>0 表示仍有未签决策，见 docs/adr/README.md）"

if [ "$fail" -eq 0 ]; then echo "✔ doctor 通过"; else echo "✗ doctor 失败"; exit 1; fi
