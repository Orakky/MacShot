import Foundation

/// 手动检查更新的**纯逻辑**（`ADR-023`）：版本号比较、清单解码、结论分类。
/// 网络与 UI 一点都不在这里——这样判据不需要联网、不需要真发布就能跑（`V-064`）。
///
/// 隐私面：本文件**不发起任何请求**。唯一的出网点是 `App/MSUpdater.swift`，
/// 且只有用户点「检查更新…」才会走（`NFR-030` 的修订见 `ADR-023`，门禁 `check-style.sh` 认这个文件）。
public struct MSVersion: Comparable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    public let parts: [Int]
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }
        var nums: [Int] = []
        for p in pieces {
            // 允许 "0.2" / "0.2.0-beta"：取每段前导数字，非数字尾巴忽略
            let digits = p.prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(digits) else { return nil }
            nums.append(n)
        }
        parts = nums
    }
    public init?(description text: String) { self.init(text) }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    /// 短的补零对齐再逐段比：`0.2` == `0.2.0`，`0.10.0` > `0.9.0`（字符串比较会把它判反）
    private static func padded(_ a: [Int], _ b: [Int]) -> ([Int], [Int]) {
        let n = max(a.count, b.count)
        return (a + Array(repeating: 0, count: n - a.count), b + Array(repeating: 0, count: n - b.count))
    }
    public static func < (lhs: MSVersion, rhs: MSVersion) -> Bool {
        let (l, r) = padded(lhs.parts, rhs.parts)
        return l.lexicographicallyPrecedes(r)
    }
    public static func == (lhs: MSVersion, rhs: MSVersion) -> Bool {
        let (l, r) = padded(lhs.parts, rhs.parts)
        return l == r
    }
}

/// GitHub Release 上那份 `latest.json` 的形状。字段少而硬：版本、说明、资产 URL、SHA-256、字节数。
public struct MSUpdateManifest: Codable, Sendable, Equatable {
    public struct Asset: Codable, Sendable, Equatable {
        public var name: String
        public var url: String
        public var sha256: String
        public var bytes: Int
        public init(name: String, url: String, sha256: String, bytes: Int) {
            self.name = name; self.url = url; self.sha256 = sha256; self.bytes = bytes
        }
    }
    public var version: String
    public var notes: String
    public var assets: [Asset]

    public init(version: String, notes: String, assets: [Asset]) {
        self.version = version; self.notes = notes; self.assets = assets
    }

    public enum Decision: Sendable, Equatable {
        case upToDate(current: String, latest: String)
        case available(Asset, latestVersion: String, currentVersion: String)
        case malformed(String)
    }

    /// 结论只由**纯比较**得出：网络失败一类由调用方（App 层）自己归类，这里不掺。
    public func decide(current: String, preferringExtension: String = "dmg") -> Decision {
        guard let latest = MSVersion(version), let now = MSVersion(current) else {
            return .malformed("版本号读不懂：清单=\(version) 本机=\(current)")
        }
        if latest <= now { return .upToDate(current: current, latest: version) }
        guard let asset = assets.first(where: { $0.url.hasSuffix(".\(preferringExtension)") }) ?? assets.first else {
            return .malformed("清单里没有 \(preferringExtension) 资产")
        }
        // 校验和必须是 64 位十六进制：短一点、长一点、带空格都算清单坏，不许"试试看"
        let sum = asset.sha256.lowercased()
        guard sum.count == 64, sum.allSatisfy({ $0.isHexDigit }) else {
            return .malformed("资产 \(asset.name) 的 sha256 不是 64 位十六进制")
        }
        guard asset.bytes > 0 else { return .malformed("资产 \(asset.name) 的字节数不合法") }
        return .available(asset, latestVersion: version, currentVersion: current)
    }
}

public enum MSUpdateSource {
    /// 默认源：GitHub Releases 的固定下载路径，公开可读、**不需要 token**。
    public static let defaultManifestURL = "https://github.com/Orakky/MacShot/releases/latest/download/latest.json"
    /// 测试与自建源可覆盖（判据用 `file://` 跑全流程，不靠联网）。
    public static func manifestURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let raw = environment["MACSHOT_UPDATE_URL"] ?? defaultManifestURL
        return URL(string: raw)
    }
}
