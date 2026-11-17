import AppKit
import CoreGraphics
import MSAnnotate

/// 工具条图标的**装载与着色**（事实表在 `MSAnnotationIconTable`，§5）。
///
/// 这一份与 `MSPinIcons` 内容相同，是**有意的重复**：`check-deps` 不许 `MSAnnotate` import AppKit，
/// 而 SF Symbols 只能经 `NSImage` 取，两个 UI 模块又都要用。真正的事实（哪个工具哪个符号）只有一份。
/// 收拢成共享 UI-kit 模块 = 一条 ADR（已登记 `B-031`）。
///
/// 纪律：符号取不到 ⇒ 返回 false，调用方**必须回落字母**，绝不画空白。
@MainActor
public enum MSOverlayIcons {
    private static var cache: [String: CGImage] = [:]

    /// 取图形蒙版；`nil` ⇒ 这台机器没有这个符号。
    public static func mask(for tool: MSTool, side: CGFloat = MSAnnotationIconTable.side) -> CGImage? {
        let key = "\(tool.rawValue):\(Int(side))"
        if let hit = cache[key] { return hit }
        guard let name = MSAnnotationIconTable.symbolName(for: tool) else {
            // 折线箭头：纯 CG 自绘， rasterize 一次进缓存。
            let made = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.addPath(MSAnnotationIconTable.polylinePath(in: rect))
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(max(1.2, 1.6 * rect.width / 12))
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.strokePath()
                return true
            }
            var r = NSRect(x: 0, y: 0, width: side, height: side)
            let cg = made.cgImage(forProposedRect: &r, context: nil, hints: nil)
            if let cg { cache[key] = cg }
            return cg
        }
        guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: name) else { return nil }
        sym.isTemplate = true
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let cg = sym.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache[key] = cg
        return cg
    }

    /// 画进格子：拿 alpha 当蒙版填一次颜色，所以 `accent` / `label` 走同一条路径。
    /// 返回 false ⇒ 调用方改画字母。
    @discardableResult
    public static func draw(_ tool: MSTool, in box: CGRect, tint: NSColor,
                            side: CGFloat = MSAnnotationIconTable.side) -> Bool {
        guard let m = mask(for: tool, side: side), let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let rect = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        ctx.saveGState()
        ctx.clip(to: rect, mask: m)
        tint.setFill()
        ctx.fill(rect)
        ctx.restoreGState()
        return true
    }

    /// 给核对表与回落路径做测试用：未知符号名必须是 nil，而不是空图。
    public static func mask(symbolName: String, side: CGFloat = 16) -> CGImage? {
        guard let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName) else { return nil }
        sym.isTemplate = true
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        return sym.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
