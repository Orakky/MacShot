import CoreGraphics
import Foundation

/// sRGB 8-bit colour — the one colour type in the project. Lives in `MSCore` because the sampler
/// (loupe / colour picker), the annotation model and the export path all need it (`ADR-012`:
/// cross-module types sink here rather than getting parallel definitions).
public struct MSColorRGBA: Hashable, Sendable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> MSColorRGBA { .init(red: r, green: g, blue: b) }
    public static func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: Double) -> MSColorRGBA { .init(red: r, green: g, blue: b, alpha: a) }
    public static let opaqueBlack = MSColorRGBA(red: 0, green: 0, blue: 0, alpha: 1)
    public static let clear = MSColorRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: CGFloat(alpha))
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when alpha matters — the format the loupe copies (`FR-CAP-014`).
    public func hex(includeAlpha: Bool = false) -> String {
        let body = String(format: "%02X%02X%02X", red, green, blue)
        return includeAlpha && alpha < 1 ? "#" + body + String(format: "%02X", Int((alpha * 255).rounded())) : "#" + body
    }

    public var rgbDescription: String { "rgb(\(red), \(green), \(blue))" }

    public var hslDescription: String {
        let r = CGFloat(red) / 255, g = CGFloat(green) / 255, b = CGFloat(blue) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let l = (maxC + minC) / 2
        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        var h: CGFloat = 0
        if delta != 0 {
            switch maxC {
            case r: h = (g - b) / delta + (g < b ? 6 : 0)
            case g: h = (b - r) / delta + 2
            default: h = (r - g) / delta + 4
            }
            h *= 60
        }
        return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 8 {
            alpha = Double((v >> 24) & 0xFF) / 255
            red = UInt8((v >> 16) & 0xFF); green = UInt8((v >> 8) & 0xFF); blue = UInt8(v & 0xFF)
        } else {
            alpha = 1
            red = UInt8((v >> 16) & 0xFF); green = UInt8((v >> 8) & 0xFF); blue = UInt8(v & 0xFF)
        }
    }
}

public enum MSImageSampler {
    public static func bitmap(from image: CGImage) -> MSBitmap? { MSBitmap(image: image) }

    public static func sample(_ image: CGImage, pixelAt point: MSIntPoint) -> MSColorRGBA? {
        bitmap(from: image)?.sample(pixelAt: point)
    }

    /// Nearest-neighbour magnified crop for the loupe: no interpolation, so pixels stay square
    /// (`FR-CAP-014`, `design/screens.md#UI-008`).
    public static func magnified(_ image: CGImage, center: MSIntPoint, radius: Int, zoom: Int) -> CGImage? {
        let side = max(1, radius * 2 + 1)
        let full = MSIntRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let src = full.intersection(MSIntRect(x: center.x - radius, y: center.y - radius, width: side, height: side)),
              let cropped = image.cropping(to: src.cgRect) else { return nil }
        let z = max(1, zoom)
        guard let dest = CGContext(data: nil, width: src.width * z, height: src.height * z, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        dest.interpolationQuality = .none
        dest.draw(cropped, in: CGRect(x: 0, y: 0, width: src.width * z, height: src.height * z))
        return dest.makeImage()
    }
}

/// A decoded RGBA8 copy of a `CGImage`. Byte layout of pixel (x, y) is `row(y) + x*4`.
/// One decode serves many samples: the loupe polls per mouse-moved event and must not redraw
/// the whole image each time.
public final class MSBitmap: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let bytes: [UInt8]

    public init?(image: CGImage) {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.width = w; self.height = h; self.bytesPerRow = w * 4; self.bytes = buffer
    }

    public func sample(pixelAt p: MSIntPoint) -> MSColorRGBA? {
        guard (0..<width).contains(p.x), (0..<height).contains(p.y) else { return nil }
        let i = p.y * bytesPerRow + p.x * 4
        return MSColorRGBA(red: bytes[i], green: bytes[i + 1], blue: bytes[i + 2], alpha: Double(bytes[i + 3]) / 255)
    }

    /// Average colour of a neighbourhood — the loupe's average readout and the `pixelate` blocks.
    public func average(in rect: MSIntRect) -> MSColorRGBA? {
        guard let r = rect.intersection(MSIntRect(x: 0, y: 0, width: width, height: height)), !r.isEmpty else { return nil }
        var a = 0, sr = 0, sg = 0, sb = 0, n = 0
        for y in r.minY..<r.maxY {
            for x in r.minX..<r.maxX {
                let i = y * bytesPerRow + x * 4
                sr += Int(bytes[i]); sg += Int(bytes[i + 1]); sb += Int(bytes[i + 2]); a += Int(bytes[i + 3]); n += 1
            }
        }
        guard n > 0 else { return nil }
        return MSColorRGBA(red: UInt8(sr / n), green: UInt8(sg / n), blue: UInt8(sb / n), alpha: Double(a / n) / 255)
    }

    /// Copy a region out as tightly packed RGBA8 rows (blur / pixelate work on this).
    public func rgbaBytes(in rect: MSIntRect) -> [UInt8]? {
        guard let r = rect.intersection(MSIntRect(x: 0, y: 0, width: width, height: height)), !r.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: r.width * r.height * 4)
        for y in 0..<r.height {
            let src = (r.minY + y) * bytesPerRow + r.minX * 4
            guard src + r.width * 4 <= bytes.count else { return nil }
            for x in 0..<(r.width * 4) { out[y * r.width * 4 + x] = bytes[src + x] }
        }
        return out
    }
}
