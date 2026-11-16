#!/bin/sh
# 依赖方向门禁（ADR-012 / NFR-012 / V-029）。反向边或环 = 失败。
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

allowed() {
  case "$1" in
    MSCore)      echo "" ;;
    MSSettings)  echo "MSCore" ;;
    MSHotKey)    echo "MSCore" ;;
    MSCapture)   echo "MSCore MSSettings" ;;
    MSAnnotate)  echo "MSCore" ;;
    MSOverlay)   echo "MSCore MSCapture MSAnnotate MSSettings" ;;
    MSPin)       echo "MSCore MSSettings MSAnnotate" ;;
    MSExport)    echo "MSCore MSAnnotate" ;;
    MSSession)   echo "MSCore MSCapture MSOverlay MSAnnotate MSPin MSExport MSHotKey MSSettings" ;;
    MSTestSupport) echo "MSCore MSCapture MSAnnotate MSSession MSHotKey MSExport MSOverlay" ;;
    *) echo "?" ;;
  esac
}

fail=0
for dir in Packages/MacShotKit/Sources/*/; do
  mod=$(basename "$dir")
  allow=$(allowed "$mod")
  [ "$allow" = "?" ] && { echo "✗ 未在门禁表中的模块：$mod（改 scripts/check-deps.sh 与 docs/architecture/modules.md）"; fail=1; continue; }
  imports=$(grep -rhoE '^import MS[A-Za-z]+' "$dir" 2>/dev/null | awk '{print $2}' | sort -u)
  for imp in $imports; do
    [ "$imp" = "$mod" ] && continue
    case " $allow " in
      *" $imp "*) : ;;
      *) echo "✗ $mod 不允许 import $imp（允许：${allow:-无}）"; fail=1 ;;
    esac
  done
done

# 模块不得依赖 App
if grep -rqE '^import MacShotKit' App 2>/dev/null && grep -rqE '^import AppKit' Packages/MacShotKit/Sources/MSCore 2>/dev/null; then
  : # placeholder，真实检查在下面：MSCore 里出现 AppKit 即失败
fi
if grep -rqE '^import (AppKit|SwiftUI)' Packages/MacShotKit/Sources/MSCore Packages/MacShotKit/Sources/MSAnnotate 2>/dev/null; then
  echo "✗ MSCore / MSAnnotate 里出现了 AppKit 或 SwiftUI（annotate-model.md：标注模型不持窗口）"
  grep -rnE '^import (AppKit|SwiftUI)' Packages/MacShotKit/Sources/MSCore Packages/MacShotKit/Sources/MSAnnotate | head -4
  fail=1
fi

[ "$fail" -eq 0 ] && echo "✔ check-deps 通过（依赖方向与 modules.md 一致）" || { echo "✗ check-deps 失败"; exit 1; }
