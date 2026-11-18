#!/bin/sh
# `vision.md` §4 的 G-01…G-05 计数：只读**本地 unified log**，不联网、不遥测（NFR-030/032）。
# 用法：sh scripts/usage-report.sh [时长，默认 7d]     例：sh scripts/usage-report.sh 60m
#
# 三条纪律：
#   1. 只数真 app（`process == "MacShot"`）——测试跑出来的 `illegal migration` 是**故意的**，
#      混进指标会把 G-05 算成灾难。
#   2. 读不到数据就说"无数据"，**不许把 0 当达标**（`E-076`）。
#   3. 计数标记由代码保证格式统一：`commit intent=`、`edit enter`、`t.hotkey→frozen`。
set -u
window=${1:-7d}
LOG=/usr/bin/log          # 必须绝对路径：某些 shell 里有 `log` 函数会把它吃掉（E-076 踩过）
[ -x "$LOG" ] || { echo "✗ 找不到 /usr/bin/log"; exit 2; }

case "${*}" in
  *--include-tests*)
    # 自校验档：把测试进程的事件也算进来，用来证明**下面的 grep 模式真能命中**。
    # 没有这一档，"0 次"分不清是"没数据"还是"我的模式写错了"——这是 `E-076` 记的教训。
    predicate='subsystem == "com.macshot.app"' ;;
  *) predicate='process == "MacShot" and subsystem == "com.macshot.app"' ;;
esac
dump=$("$LOG" show --last "$window" --info --predicate "$predicate" --style compact 2>/dev/null | grep -v 'com.apple.log')
if [ -z "$dump" ]; then
  echo "✗ 窗口 $window 内没有 MacShot 的日志 ⇒ **无数据**，不是达标。"
  echo "  先确认 app 真跑过（make run），且这台机器的日志留存够长。"
  exit 3
fi
count() { printf '%s\n' "$dump" | grep -c "$1"; }

frozen=$(count 't\.hotkey→frozen')
pins=$(count 'commit intent=pin')
copies=$(count 'commit intent=copy')
saves=$(count 'commit intent=savePanel')
qsaves=$(count 'commit intent=quickSave')
cancels=$(count 'commit intent=cancel')
edits=$(count 'edit enter')
perm=$(count 'capture\.perm-missing')
degenerate=$(count 'degenerate=true')
illegal=$(count 'illegal migration')
commits=$((pins + copies + saves + qsaves + cancels))

echo "=== 使用计数（窗口 $window，predicate: $predicate）==="
echo "G-01 首版真的被日常使用      : t.hotkey→frozen = $frozen 次（达标线 ≥20/天 × 连续 5 天）"
printf 'G-03 贴图的对照用途         : pin=%s copy=%s save=%s quickSave=%s cancel=%s ⇒ pin 占比 ' \
  "$pins" "$copies" "$saves" "$qsaves" "$cancels"
if [ "$commits" -gt 0 ]; then
  awk -v p="$pins" -v t="$commits" 'BEGIN{printf "%.1f%%（达标线 ≥20%%）\n", p*100/t}'
else echo "无提交事件 ⇒ 无数据"; fi
printf 'G-04 再编辑值得它的代价     : edit enter=%s / pin=%s ⇒ ' "$edits" "$pins"
if [ "$pins" -gt 0 ]; then
  awk -v e="$edits" -v p="$pins" 'BEGIN{printf "%.1f%%（达标线 ≥15%%；低于它要回 Q-12 重议）\n", e*100/p}'
else echo "无贴图 ⇒ 无数据"; fi
echo "G-05 无静默黑图事故           : perm-missing=$perm degenerate=$degenerate（红线是 degenerate=0）"
[ "$illegal" -gt 0 ] && echo "  注：illegal migration 计数=$illegal（状态机被拒的迁移，正常应为 0，值得查）"
echo "G-02 没有被嫌麻烦绕过         : 无法从日志观察 ⇒ 你自己确认（一周内用系统截图+预览裁剪的次数）"
