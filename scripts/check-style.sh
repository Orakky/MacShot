#!/bin/sh
# 风格门禁（ADR-015：不装 lint，用脚本）。FAIL = 不许提交；WARN = 记账但放行。
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# 只扫自己的源码：.build 里是 SPM 生成的测试 runner，不受我们的规范管
SRC="App Packages/MacShotKit/Sources Packages/MacShotKit/Tests"
fail=0

ban() {  # ban <说明> <grep -E 模式> [排除文件 glob]
  label="$1"; pattern="$2"; exclude="${3:-}"
  if [ -n "$exclude" ]; then
    hits=$(grep -rn --include='*.swift' -E "$pattern" $SRC 2>/dev/null | grep -v -E "$exclude" || true)
  else
    hits=$(grep -rn --include='*.swift' -E "$pattern" $SRC 2>/dev/null || true)
  fi
  if [ -n "$hits" ]; then
    n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    echo "✗ $label — $n 处"
    printf '%s\n' "$hits" | head -6 | sed "s|$(pwd)/||; s|^|    |"
    fail=1
  else
    echo "✔ $label"
  fi
}

ban "禁用 try!"                     'try!'
ban "禁用 as!"                      ' as! '
ban "禁用 fatalError（除显式契约点）" 'fatalError\(' 'init\?\(coder'
ban "禁止网络/遥测（NFR-030）"        'URLSession|NCConnection|CLLocationManager'
ban "禁止造全局单例（系统 API 除外）"  '(NSApp|Self|[A-Z][A-Za-z]*)\.shared' \
  '(App/|ButtonBox|sharedHandler|NSWorkspace|NSApplication|NSColor|NSFont|NSScreen|NSPasteboard|NSUIElement|Logger|NSDocumentController)'

# 中文文案最终应收敛到 MSStrings（ADR-016 尚未实现）→ 目前只报告不拦
zh=$(python3 - "$SRC" <<'PYEOF'
import pathlib, re, sys
total = 0
for base in sys.argv[1].split():
    for p in pathlib.Path(base).rglob("*.swift"):
        if re.search(r"[\u4e00-\u9fff]", p.read_text(encoding="utf-8", errors="ignore")):
            total += 1
print(total)
PYEOF
)
echo "⚠ 含中文的 .swift 文件 $zh 个（ADR-016 落地后应只剩 MSStrings.swift 与测试夹具）"

over=$(find $SRC -name '*.swift' -print0 2>/dev/null | xargs -0 awk 'FNR==401 { print FILENAME }' 2>/dev/null)
if [ -n "$over" ]; then
  echo "⚠ 超过 400 行的文件（NFR-033，需拆）:"
  printf '%s\n' "$over" | sed "s|$(pwd)/||; s|^|    |"
else
  echo "✔ 文件长度全部 ≤400 行"
fi

[ "$fail" -eq 0 ] && { echo "✔ check-style 通过"; } || { echo "✗ check-style 失败"; exit 1; }
