import CoreGraphics
import CoreText
import Foundation
import MSCore

/// Where a frame is going. The same document must produce the same pixels in all three
/// (`annotate-model.md` §5 requirement 1) — that invariant is what stops "on screen pink,
/// exported black" class bugs.
public enum MSRenderIntent: String, Sendable { case preview, pin, export }

public protocol MSAnnotationRendering: Sendable {
    /// Returns an image exactly `document.canvasSize` pixels; never resamples the source.
    func render(_ document: MSAnnotationDocument, source: CGImage?, intent: MSRenderIntent) -> CGImage?
}

/// Document space is y-down (canvas pixels); a bare `CGContext` is y-up. The whole flip is
/// confined to `render`: element drawing below only ever sees y-down coordinates, and the two
/// places that must escape the flip (source image, text runs) un-flip locally.
public struct MSAnnotationRenderer: MSAnnotationRendering {
    public init() {}

    public func render(_ document: MSAnnotationDocument, source: CGImage?, intent: MSRenderIntent) -> CGImage? {
        let size = document.canvasSize
        guard size.width > 0, size.height > 0,
              let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let h = CGFloat(size.height)
        ctx.interpolationQuality = .none
        ctx.setFillColor(MSColorRGBA.clear.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        if let source { ctx.draw(source, in: CGRect(x: 0, y: 0, width: size.width, height: size.height)) }

        renderElements(of: document, into: ctx, source: source, canvas: size, intent: intent)
        _ = h
        return ctx.makeImage()
    }

    /// Draws only the element layer, into a caller-configured context that must already be in
    /// document space (y-down, one unit = one canvas pixel) and optionally pre-scaled by the
    /// display factor. `MSPin` uses this to scale the bitmap while redrawing vectors at native
    /// resolution — the property `FR-PIN-003` depends on.
    public func renderElements(of document: MSAnnotationDocument, into ctx: CGContext,
                               source: CGImage?, canvas: MSIntSize, intent: MSRenderIntent) {
        let h = CGFloat(canvas.height)
        for element in document.sortedElements {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: h)
            ctx.scaleBy(x: 1, y: -1)                       // → document space, y-down
            draw(element, in: ctx, source: source, canvas: canvas, intent: intent)
            ctx.restoreGState()
        }
    }

    // MARK: - per kind (all coordinates below are document space, y-down)

    private func draw(_ e: MSAnnotationElement, in ctx: CGContext, source: CGImage?,
                      canvas: MSIntSize, intent: MSRenderIntent) {
        let s = e.style
        ctx.saveGState()
        ctx.setLineWidth(CGFloat(max(1, s.lineWidth)))
        ctx.setLineJoin(.round)
        ctx.setLineCap(s.dash == .dot ? .round : .butt)
        switch s.dash {
        case .solid: ctx.setLineDash(phase: 0, lengths: [])
        case .dash: ctx.setLineDash(phase: 0, lengths: [CGFloat(s.lineWidth) * 3, CGFloat(s.lineWidth) * 2])
        case .dot: ctx.setLineDash(phase: 0, lengths: [1, CGFloat(max(2, s.lineWidth) * 2)])
        }

        switch e.kind {
        case .rect:
            guard let r = MSAnnotationGeometry.bounds(of: e), r.width > 0 || r.height > 0 else { break }
            let path = CGPath(roundedRect: r.cgRect, cornerWidth: CGFloat(s.cornerRadius),
                              cornerHeight: CGFloat(s.cornerRadius), transform: nil)
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.addPath(path); ctx.fillPath() }
            ctx.setStrokeColor(s.stroke.cgColor); ctx.addPath(path); ctx.strokePath()

        case .ellipse:
            guard let r = MSAnnotationGeometry.bounds(of: e) else { break }
            if let fill = s.fill { ctx.setFillColor(fill.cgColor); ctx.fillEllipse(in: r.cgRect) }
            ctx.setStrokeColor(s.stroke.cgColor); ctx.strokeEllipse(in: r.cgRect)

        case .line, .arrow:
            guard e.points.count >= 2 else { break }
            ctx.setStrokeColor(s.stroke.cgColor)
            ctx.move(to: pt(e.points[0])); ctx.addLine(to: pt(e.points[1])); ctx.strokePath()
            if e.kind == .arrow { drawArrowHead(from: e.points[0], to: e.points[1], style: s, in: ctx) }

        case .polyline:
            guard e.points.count >= 2 else { break }
            ctx.setStrokeColor(s.stroke.cgColor); ctx.addLines(between: e.points.map(pt)); ctx.strokePath()
            if e.points.count >= 2 {
                drawArrowHead(from: e.points[e.points.count - 2], to: e.points[e.points.count - 1], style: s, in: ctx)
            }

        case .freehand:
            guard e.points.count >= 2 else { break }
            ctx.setStrokeColor(s.stroke.cgColor)
            if e.isPen {
                ctx.setLineWidth(CGFloat(max(1, s.lineWidth)))
            } else {
                ctx.setBlendMode(.multiply); ctx.setAlpha(0.45)
                ctx.setLineWidth(CGFloat(max(1, s.lineWidth)) * 3.2)
            }
            ctx.addLines(between: e.points.map(pt)); ctx.strokePath()

        case .text:
            guard let o = e.points.first else { break }
            drawText(e.text, origin: o, style: s, color: s.stroke, canvasHeight: canvas.height, in: ctx)

        case .badge:
            guard let c = e.points.first else { break }
            let r = CGFloat(MSAnnotationGeometry.badgeRadius(for: e))
            ctx.setFillColor(s.stroke.cgColor)
            ctx.fillEllipse(in: CGRect(x: CGFloat(c.x) - r, y: CGFloat(c.y) - r, width: r * 2, height: r * 2))
            drawTextCentered(e.text, center: CGPoint(x: c.x, y: c.y), radius: r, in: ctx)

        case .blur:
            guard let r = MSAnnotationGeometry.bounds(of: e), let source,
                  let blurred = MSImageOps.blurred(from: source, region: r, style: s) else { break }
            // The blurred tile is a CGImage (top-left origin); un-flip so it lands upright.
            ctx.saveGState()
            ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: CGRect(x: r.minX, y: -(r.maxY), width: r.width, height: r.height))
            ctx.draw(blurred, in: CGRect(x: r.minX, y: -(r.maxY), width: r.width, height: r.height))
            ctx.restoreGState()

        case .eraser, .spotlight, .crop:
            break   // eraser deletes elements instead of marking; spotlight/crop are P1
        }
        ctx.restoreGState()
    }

    private func pt(_ p: MSIntPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private func drawArrowHead(from a: MSIntPoint, to b: MSIntPoint, style s: MSAnnotationStyle, in ctx: CGContext) {
        let angle = atan2(Double(b.y - a.y), Double(b.x - a.x))
        let size = max(8, CGFloat(s.lineWidth) * 3.4)
        let spread = s.arrowHead == .triangle ? 0.42 : 0.5
        let rotations: [Double] = s.arrowHead == .double ? [0, .pi] : [0]
        ctx.setFillColor(s.stroke.cgColor); ctx.setLineDash(phase: 0, lengths: [])
        for rot in rotations {
            let left = CGPoint(x: b.x - Int(cos(angle - spread + rot) * Double(size)),
                               y: b.y - Int(sin(angle - spread + rot) * Double(size)))
            let right = CGPoint(x: b.x - Int(cos(angle + spread + rot) * Double(size)),
                                y: b.y - Int(sin(angle + spread + rot) * Double(size)))
            ctx.beginPath(); ctx.move(to: pt(b)); ctx.addLine(to: left); ctx.addLine(to: right)
            ctx.closePath(); ctx.fillPath()
        }
    }

    // MARK: - text (CoreText keeps this module AppKit-free; runs un-flip locally)

    /// System font through CoreText only: `NSAttributedString.Key.font` lives in AppKit, and this
    /// module must not depend on it (`modules.md` §6, enforced by scripts/check-deps.sh).
    private func font(_ size: Int, bold: Bool) -> CTFont {
        let pt = CGFloat(max(6, size))
        let base: CTFont
        if let ui = CTFontCreateUIFontForLanguage(.system, pt, nil) {
            base = ui
        } else {
            base = CTFontCreateWithName("Helvetica" as CFString, pt, nil)
        }
        guard bold else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, pt, nil, .traitBold, .traitBold) ?? base
    }

    private func line(_ text: String, font: CTFont, color: MSColorRGBA) -> CTLine? {
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: color.cgColor]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return nil }
        return CTLineCreateWithAttributedString(attributed)
    }

    private func drawText(_ text: String, origin: MSIntPoint, style s: MSAnnotationStyle,
                          color: MSColorRGBA, canvasHeight: Int, in ctx: CGContext) {
        let f = font(s.fontSize, bold: s.bold)
        let lines = text.components(separatedBy: "\n")
        let lh = CGFloat(max(8, s.fontSize)) * 1.32
        for (i, raw) in lines.enumerated() where !raw.isEmpty {
            guard let rendered = line(raw, font: f, color: color) else { continue }
            ctx.saveGState()
            // Baseline sits fontSize below the line-box top; un-flip around that point.
            ctx.translateBy(x: CGFloat(origin.x), y: -(CGFloat(origin.y) + CGFloat(i) * lh + CGFloat(s.fontSize)))
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(rendered, ctx)
            ctx.restoreGState()
        }
    }

    private func drawTextCentered(_ text: String, center: CGPoint, radius: CGFloat, in ctx: CGContext) {
        guard let rendered = line(text, font: font(Int(radius * 1.15), bold: true), color: .rgb(255, 255, 255)) else { return }
        let b = CTLineGetBoundsWithOptions(rendered, .useOpticalBounds)
        ctx.saveGState()
        ctx.translateBy(x: center.x - CGFloat(b.midX), y: -center.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(rendered, ctx)
        ctx.restoreGState()
    }
}

enum MSImageOps {
    /// `pixelate` is a true block average on an integer block grid; `gaussian` is a separable
    /// box approximation. `ADR-021` may replace the latter with `CIFilter` once measured —
    /// P0 keeps both dependency-free and byte-deterministic, which is exactly what the
    /// preview-equals-export test needs.
    static func blurred(from source: CGImage, region: MSIntRect, style: MSAnnotationStyle) -> CGImage? {
        guard let bmp = MSBitmap(image: source), !region.isEmpty else { return nil }
        let w = region.width, h = region.height
        switch style.blurKind {
        case .pixelate:
            let block = max(2, style.blurRadius)
            var out = [UInt8](repeating: 0, count: w * h * 4)
            for by in stride(from: 0, to: h, by: block) {
                for bx in stride(from: 0, to: w, by: block) {
                    let sub = MSIntRect(x: region.minX + bx, y: region.minY + by,
                                        width: min(block, w - bx), height: min(block, h - by))
                    let avg = bmp.average(in: sub) ?? .opaqueBlack
                    for y in by..<min(by + block, h) {
                        for x in bx..<min(bx + block, w) {
                            let i = (y * w + x) * 4
                            out[i] = avg.red; out[i + 1] = avg.green; out[i + 2] = avg.blue; out[i + 3] = 255
                        }
                    }
                }
            }
            return image(from: out, width: w, height: h)
        case .gaussian:
            guard var px = bmp.rgbaBytes(in: region) else { return nil }
            let radius = max(1, style.blurRadius / 2)
            boxBlur(&px, w: w, h: h, radius: radius)
            boxBlur(&px, w: w, h: h, radius: radius)
            return image(from: px, width: w, height: h)
        }
    }

    private static func image(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        var data = bytes
        return data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    /// Separable box blur: horizontal pass writes a new buffer, vertical pass reads that buffer.
    private static func boxBlur(_ px: inout [UInt8], w: Int, h: Int, radius: Int) {
        let span = UInt32(radius * 2 + 1)
        var tmp = [UInt32](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var acc: [UInt32] = [0, 0, 0, 0]
                for k in max(0, x - radius)...min(w - 1, x + radius) {
                    let i = (y * w + k) * 4
                    for c in 0..<4 { acc[c] += UInt32(px[i + c]) }
                }
                let i = (y * w + x) * 4
                for c in 0..<4 { tmp[i + c] = acc[c] / span }
            }
        }
        for x in 0..<w {
            for y in 0..<h {
                var acc: [UInt32] = [0, 0, 0, 0]
                for k in max(0, y - radius)...min(h - 1, y + radius) {
                    let i = (k * w + x) * 4
                    for c in 0..<4 { acc[c] += tmp[i + c] }
                }
                let i = (y * w + x) * 4
                for c in 0..<4 { px[i + c] = UInt8(min(255, acc[c] / span)) }
            }
        }
    }
}
