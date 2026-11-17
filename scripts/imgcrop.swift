#!/usr/bin/env xcrun swift -
// 用法：imgcrop <in.png> <out.png> <x> <y> <w> <h>（像素，左上原点）
// 为什么不用 sips：`sips -c` 的 --cropOffset 在这台机器上被忽略（裁剪永远居中），
// 量工具条这种"指定矩形"的活它干不了。
import AppKit
import CoreGraphics

let a = CommandLine.arguments
guard a.count == 7, let x = Int(a[3]), let y = Int(a[4]), let w = Int(a[5]), let h = Int(a[6]),
      let img = NSImage(contentsOfFile: a[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let crop = cg.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
    FileHandle.standardError.write("用法: imgcrop <in> <out> <x> <y> <w> <h>\n".data(using: .utf8)!)
    exit(2)
}
let rep = NSBitmapImageRep(cgImage: crop)
guard let data = rep.representation(using: .png, properties: [:]) else { print("FAIL 编码"); exit(3) }
try data.write(to: URL(fileURLWithPath: a[2]))
print("→ \(a[2]) \(crop.width)x\(crop.height)")
