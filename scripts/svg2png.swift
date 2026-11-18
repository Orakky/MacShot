import AppKit
import CoreGraphics
import ImageIO
import Foundation

/// `svg2png <in.svg> <out.png> <边长pt> [底色=none|white]`
///
/// 存在的理由：`qlmanage` 光栅化 SVG 时会把画布刷成**不透明白底**（实测 1024² 里透明像素 = 0），
/// 于是 app 图标变成"白色方块里嵌一个圆角深色图标"（用户 11-18 报的）。AppKit 自己会解 SVG
/// 且保留 alpha（同一份真源实测透明像素 398648），所以这里只用系统框架，不引第三方（`ADR-015`）。
let a = CommandLine.arguments
guard a.count >= 4 else {
    FileHandle.standardError.write("用法: svg2png <in.svg> <out.png> <边长pt> [white]\n".data(using: .utf8)!)
    exit(1)
}
let side = Int(a[3]) ?? 1024
guard side > 0, let image = NSImage(contentsOfFile: a[1]) else {
    FileHandle.standardError.write("✗ 读不到 SVG：\(a[1])\n".data(using: .utf8)!); exit(2)
}
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(3) }
if a.count >= 5, a[4] == "white" {
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
} else {
    ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
}
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.current = nil
guard let out = ctx.makeImage() else { exit(4) }
guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                                "public.png" as CFString, 1, nil) else { exit(5) }
CGImageDestinationAddImage(dst, out, nil)
guard CGImageDestinationFinalize(dst) else { exit(6) }
print("→ \(a[2]) \(side)x\(side)")
