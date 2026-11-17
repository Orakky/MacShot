import AppKit
import Foundation

/// 两张 PNG 的像素级比较。用法：`swift scripts/imgdiff.swift a.png b.png`
/// 输出 `IDENTICAL` 或 `changed=<像素数> bbox=x,y..x,y size=WxH maxΔ=<0…255>`。
/// 存在的理由：`probe-freeze` 要判"遮罩期间背景全程不变"，这条判据只能是数，不能是目视。
func bitmap(_ path: String) -> NSBitmapImageRep? {
    guard let data = FileManager.default.contents(atPath: path),
          let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep
}

let args = CommandLine.arguments
// 可选：--exclude x0 y0 x1 y1 跳过一块区域。系统画在所有窗之上的浮层（录屏指示器会脉动）
// 不属于"背景在动"，但必须单独量出来写清楚，不能悄悄忽略。
var excl: (x0: Int, y0: Int, x1: Int, y1: Int)?
if let i = args.firstIndex(of: "--exclude"), args.count >= i + 5,
   let x0 = Int(args[i + 1]), let y0 = Int(args[i + 2]),
   let x1 = Int(args[i + 3]), let y1 = Int(args[i + 4]),
   x0 >= 0, y0 >= 0, x1 > x0, y1 > y0 {
    excl = (x0, y0, x1, y1)
}
// 位置参数：跳过 --exclude 与紧跟的四个数字
var files: [String] = []
var skipNext = 0
for arg in args.dropFirst() {
    if skipNext > 0 { skipNext -= 1; continue }
    if arg == "--exclude" { skipNext = 4; continue }
    files.append(arg)
}
guard files.count == 2, let a = bitmap(files[0]), let b = bitmap(files[1]) else {
    print("FAIL 读图失败：files=\(files)"); exit(2)
}
guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else {
    print("changed=ALL 尺寸不同 \(a.pixelsWide)x\(a.pixelsHigh) vs \(b.pixelsWide)x\(b.pixelsHigh)"); exit(1)
}
let step = 2   // 半采样足够抓住"整块在动"，且快一个量级
var changed = 0, probed = 0, minX = a.pixelsWide, minY = a.pixelsHigh, maxX = -1, maxY = -1, maxDelta = 0
for y in stride(from: 0, to: a.pixelsHigh, by: step) {
    for x in stride(from: 0, to: a.pixelsWide, by: step) {
        if let e = excl, x >= e.x0, x <= e.x1, y >= e.y0, y <= e.y1 { continue }
        guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
        probed += 1
        let dr = abs(ca.redComponent - cb.redComponent)
        let dg = abs(ca.greenComponent - cb.greenComponent)
        let db = abs(ca.blueComponent - cb.blueComponent)
        let d = max(dr, max(dg, db)) * 255
        if d > 8 {
            changed += 1
            maxDelta = max(maxDelta, Int(d.rounded()))
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
if changed == 0 {
    print("IDENTICAL probed=\(probed) size=\(a.pixelsWide)x\(a.pixelsHigh)\(excl != nil ? " 已排除系统指示器区" : "")")
    exit(0)
}
print("changed=\(changed)/\(probed) bbox=\(minX),\(minY)..\(maxX),\(maxY) size=\(maxX - minX + 1)x\(maxY - minY + 1) maxΔ=\(maxDelta)")
exit(1)
