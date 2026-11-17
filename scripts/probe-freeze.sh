#!/bin/sh
# M-2 准出判据 ① 与 ④ 的运行时取证：
#   ① 遮罩期间背景全程不变（ADR-008 的"先冻结后选区"语义）——连拍两张遮罩图必须逐像素相同
#   ④ 取消会话不写剪贴板（FR-SESS-002）——真剪贴板放哨兵，走与 Esc 同一条取消路径后哨兵必须还在
#
# 只用系统工具（screencapture / swift），不引第三方。产物落 build/freeze/，不入库。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
bin="$root/build/Derived/Build/Products/Debug/MacShot.app/Contents/MacOS/MacShot"
out="$root/build/freeze"
[ -x "$bin" ] || { echo "✗ 找不到产物 $bin（先 make appicon）"; exit 1; }
mkdir -p "$out"
rm -f "$out"/*.png

helper="$out/pb.swift"
cat > "$helper" <<'SWIFT'
import AppKit
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let pb = NSPasteboard.general
switch mode {
case "put":
    pb.clearContents()
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: 64)
    let ok = pb.setData(png, forType: .png)
    pb.setString("MACSHOT-SENTINEL-DO-NOT-TOUCH", forType: .string)
    print("put ok=\(ok) changeCount=\(pb.changeCount)")
case "get":
    let s = pb.string(forType: .string) ?? "<nil>"
    let pngBytes = pb.data(forType: .png)?.count ?? -1
    print("string=\(s) pngBytes=\(pngBytes) changeCount=\(pb.changeCount)")
default:
    print("用法：pb.swift put|get"); exit(2)
}
SWIFT

echo "→ 放哨兵"
sentinel=$(swift "$helper" put)
echo "   $sentinel"

echo "→ 拍遮罩外基线"
screencapture -x "$out/before.png"

echo "→ 开遮罩，连拍完成后自动走取消路径（最长占用 ~3s）"
"$bin" --snip-then-cancel 3000 > "$out/run.log" 2>&1 &
pid=$!
# 等遮罩真的立起来再连拍：上一版按固定 sleep 拍，结果第一张拍到的还是实况桌面
# （与实况只差 0.6%），把"没等到"误报成"背景在动"。判据必须等真凭据，不是等时间。
waited=0
while [ "$waited" -lt 60 ]; do
    if /usr/bin/log show --last 8s --info --style compact \
         --predicate 'subsystem == "com.macshot.app" and category == "capture"' 2>/dev/null \
         | grep -q "overlay shown"; then
        break
    fi
    sleep 0.1; waited=$((waited + 1))
done
if [ "$waited" = 60 ]; then echo "✗ 等了 6s 没等到 overlay shown 日志，遮罩没起来"; exit 1; fi
echo "   遮罩已出现（等了约 $(($waited / 10)).$((($waited % 10) * 1))s），开始三连拍"
# 三连拍：间隔 0.25s。人手来不及在这个窗口里拖出选区；真被操作打断时会报出来
for n in a b c; do screencapture -x "$out/during_$n.png"; sleep 0.25; done
wait "$pid" || true

echo "→ 读回哨兵"
after=$(swift "$helper" get)
echo "   $after"

echo "→ 判据①：遮罩期间三连拍必须逐像素相同"
frames_same=1
for pair in "a b" "b c" "a c"; do
    set -- $pair
    swift "$root/scripts/imgdiff.swift" "$out/during_$1.png" "$out/during_$2.png" --exclude 1850 0 1920 24 || frames_same=0
done
if [ "$frames_same" = 1 ]; then
    freeze=PASS
    echo "   三帧相同（排除右上角系统指示器区）⇒ 背景确实冻住"
elif swift "$root/scripts/imgdiff.swift" "$out/during_a.png" "$out/during_b.png"; then
    freeze=PASS-SYSTEM-ONLY
    echo "   仅系统指示器在变，已单独量出"
else
    echo "   ⚠ 有真实差异。两种可能：①有人在这 0.5 秒里动了遮罩（会出现选区/工具条）②背景真在动。"
    echo "     看上面的 bbox：整屏散布＝②；成块的矩形＝①（被打断，请重跑）"
    freeze=FAIL
fi

echo "→ 前置检查：遮罩真的起来了（基线与遮罩图必须有差）"
if swift "$root/scripts/imgdiff.swift" "$out/before.png" "$out/during_a.png" >/dev/null; then
    echo "✗ before 与 during 完全相同 ⇒ 遮罩没起来或截屏无权限，①的结论不可信"
    overlay=FAIL
else
    overlay=PASS
fi

echo "→ 判据④：取消后哨兵必须原样还在"
case "$after" in
*"MACSHOT-SENTINEL-DO-NOT-TOUCH"*) cancel=PASS ;;
*) cancel=FAIL ;;
esac

echo "→ 读数：freeze=$freeze overlay_up=$overlay clipboard_sentinel=$cancel"
echo "   会话日志：$(/usr/bin/log show --last 1m --info --style compact --predicate 'subsystem == "com.macshot.app" and category == "session"' 2>/dev/null | grep -E "probe cancel|cancelled" | tail -2 | tr '\n' ' ')"
[ "$freeze" = PASS ] || [ "$freeze" = PASS-SYSTEM-ONLY ]; [ "$freeze" != FAIL ] && [ "$cancel" = PASS ] && { echo "✔ probe-freeze 通过"; exit 0; }
echo "✗ probe-freeze 有未通过项"
exit 1
