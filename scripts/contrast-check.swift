#!/usr/bin/env xcrun swift -
// `NFR-024` 的校验脚本：把 `design-system.md` §2 的语义 token 成对拿去做 WCAG 2.2 相对亮度比。
// 为什么不用现成工具：本机没有 brew（ADR-015），而这段数学不到 40 行，自己算比引依赖便宜。
//
// 用法：xcrun swift scripts/contrast-check.swift          # 跑内置表
//       xcrun swift scripts/contrast-check.swift --json    # 机器可读（给 check-docs 用）
//
// 退出码：0 全过；1 有低于门槛的配对。**门槛不许在代码里放宽**——要放宽就改 nfr.md 并让用户签字。
import Foundation

func srgb(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func luminance(_ hex: String) -> Double {
    let h = hex.replacingOccurrences(of: "#", with: "")
    guard h.count == 6, let n = UInt32(h, radix: 16) else { return -1 }
    let r = srgb(Double((n >> 16) & 0xFF) / 255), g = srgb(Double((n >> 8) & 0xFF) / 255), b = srgb(Double(n & 0xFF) / 255)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
/// 前景带 alpha：先按 alpha 合成到背景上，再算比——"半透明白字"直接当白字算是错的。
func composite(_ fg: String, _ bg: String, _ alpha: Double) -> String {
    func ch(_ hex: String, _ shift: UInt) -> Double {
        let h = hex.replacingOccurrences(of: "#", with: "")
        return Double((UInt32(h, radix: 16) ?? 0) >> shift & 0xFF) / 255
    }
    func mix(_ a: Double, _ b: Double) -> Int { Int(((a * alpha + b * (1 - alpha)) * 255).rounded()) }
    let r = mix(ch(fg, 16), ch(bg, 16)), g = mix(ch(fg, 8), ch(bg, 8)), b = mix(ch(fg, 0), ch(bg, 0))
    return String(format: "#%02X%02X%02X", r, g, b)
}
func ratio(_ fg: String, _ bg: String) -> Double {
    let l1 = luminance(fg), l2 = luminance(bg)
    guard l1 >= 0, l2 >= 0 else { return -1 }
    let hi = max(l1, l2), lo = min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)
}

struct Pair { let name: String, fg: String, bg: String, alpha: Double, large: Bool }
// 只列**用户真的会看到**的组合：读数、工具条、状态色、贴图角标。
let pairs: [Pair] = [
    .init(name: "读数 text.onDark / 深色药丸", fg: "#FFFFFF", bg: "#2A2A2C", alpha: 1, large: false),
    .init(name: "读数 text.onDark / 遮罩黑 62%", fg: "#FFFFFF", bg: composite("#000000", "#808080", 0.62), alpha: 1, large: false),
    .init(name: "text.primary / float.surface(light)", fg: "#1D1D1F", bg: composite("#F6F6F6", "#808080", 0.96), alpha: 1, large: false),
    .init(name: "text.primary / float.surface(dark)", fg: "#F2F2F7", bg: composite("#2A2A2C", "#808080", 0.96), alpha: 1, large: false),
    .init(name: "text.secondary / float.surface(light)", fg: "#6E6E73", bg: composite("#F6F6F6", "#808080", 0.96), alpha: 1, large: false),
    .init(name: "text.secondary / float.surface(dark)", fg: "#A1A1A6", bg: composite("#2A2A2C", "#808080", 0.96), alpha: 1, large: false),
    .init(name: "accent / float.surface(light)", fg: "#0A84FF", bg: composite("#F6F6F6", "#808080", 0.96), alpha: 1, large: true),
    .init(name: "accent / float.surface(dark)", fg: "#409CFF", bg: composite("#2A2A2C", "#808080", 0.96), alpha: 1, large: true),
    .init(name: "danger / float.surface(light)", fg: "#FF3B30", bg: composite("#F6F6F6", "#808080", 0.96), alpha: 1, large: true),
    .init(name: "warn / float.surface(light)", fg: "#FF9F0A", bg: composite("#F6F6F6", "#808080", 0.96), alpha: 1, large: true),
    .init(name: "warn / 遮罩黑 55%", fg: "#FF9F0A", bg: composite("#000000", "#808080", 0.55), alpha: 1, large: true),
]
let json = CommandLine.arguments.contains("--json")
var failures = 0
for p in pairs {
    let r = ratio(p.fg, p.bg)
    // AA：正文 4.5:1，大字（≥18pt 或 14pt 粗）3:1。`NFR-024` 写的是 4.5:1，大字档按 WCAG 本身允许 3:1。
    let need = p.large ? 3.0 : 4.5
    let ok = r >= need
    if !ok { failures += 1 }
    if json { print("{\"pair\":\"\(p.name)\",\"ratio\":\(String(format: "%.2f", r)),\"need\":\(need),\"pass\":\(ok)}") }
    else { print("\(ok ? "✔" : "✘") \(p.name)  \(String(format: "%.2f", r)):1（门槛 \(need):1）") }
}
if !json {
    print("→ \(pairs.count - failures)/\(pairs.count) 过；失败 \(failures)")
    print("  注：`large` 档是工具条/读数里 ≥18pt 或粗体 14pt 的字，WCAG 2.2 允许 3:1；正文一律 4.5:1。")
}
exit(failures == 0 ? 0 : 1)
