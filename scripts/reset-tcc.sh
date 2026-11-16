#!/bin/sh
# 排查"截图全黑"的第一招：清掉 MacShot 的屏幕录制授权后重启 app（runbook/permissions-tcc.md §4）
set -e
bundle=$( /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Config/Info.plist )
echo "→ tccutil reset ScreenCapture $bundle"
tccutil reset ScreenCapture "$bundle" || true
echo "→ 下次启动 MacShot 会重新请求授权；若列表里没有它，先触发一次截图"
