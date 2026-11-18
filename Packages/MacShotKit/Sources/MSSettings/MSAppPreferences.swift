import Foundation
import MSCore

/// All persisted preferences in one value type with a schema version. Fields are append-only:
/// renaming or re-purposing one is a schema break, not a refactor (`FR-SET-003`, `ADR-009` style).
public struct MSAppPreferences: Codable, Sendable, Equatable {
    /// 3 = 删掉 `confirmBeforeDiscardingUnexportedPins`：`Q-06` 已裁"退出直接抛弃、不加确认"，
    /// 这个字段的需求前提被推翻了，留着就是"有开关、没行为"（`B-037` / `E-070`）。
    /// 2 = 剪贴板不再双写 TIFF（`Q-04`），删掉 `Export.writesPngAndTiffToPasteboard`。
    /// 读侧允许 `schemaVersion <= current`（§114），旧文件里多出来的那个键会被忽略，
    /// 所以这是一次**向前兼容**的收窄，不是迁移。
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int

    public struct HotKeys: Codable, Sendable, Equatable {
        public var snip: MSKeyCombo
        public var pinClipboard: MSKeyCombo
        public var fullScreen: MSKeyCombo
        public static let standard = HotKeys(snip: .f1,
                                             pinClipboard: .f3,
                                             fullScreen: .init(keyCode: 0, command: true))  // ⌘A
    }

    public struct Export: Codable, Sendable, Equatable {
        public var directory: String
        public var namingTemplate: String
        public var format: MSImageFormat
        public var jpegQuality: Double
        public static let standard = Export(directory: "~/Pictures/MacShot",
                                            namingTemplate: "MacShot {yyyy}-{MM}-{dd} {HH}.{mm}.{ss}",
                                            format: .png, jpegQuality: 0.9)
    }

    /// Which action the commit key performs (`Q-05` / `FR-PIN-018`). Default is pin: capture is
    /// most often followed by "stick it up and look".
    public enum CommitBehavior: String, Codable, Sendable, CaseIterable {
        case pin, copy, save
        public var label: String {
            switch self { case .pin: "贴出"; case .copy: "复制"; case .save: "保存到文件" }
        }
    }

    public struct AnnotationDefaults: Codable, Sendable, Equatable {
        public var strokeHex: String
        public var lineWidth: Int
        public var fontSize: Int
        public var blurRadius: Int
        public static let standard = AnnotationDefaults(strokeHex: "#E83347", lineWidth: 3,
                                                        fontSize: 18, blurRadius: 12)
    }

    public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }

    public var hotKeys: HotKeys
    public var export: Export
    public var commitBehavior: CommitBehavior
    public var appearance: Appearance
    public var annotationDefaults: AnnotationDefaults
    public var showMagnifierWhileDragging: Bool

    public init(schemaVersion: Int = MSAppPreferences.currentSchemaVersion,
                hotKeys: HotKeys = .standard,
                export: Export = .standard,
                commitBehavior: CommitBehavior = .pin,
                appearance: Appearance = .system,
                annotationDefaults: AnnotationDefaults = .standard,
                showMagnifierWhileDragging: Bool = true) {
        self.schemaVersion = schemaVersion
        self.hotKeys = hotKeys
        self.export = export
        self.commitBehavior = commitBehavior
        self.appearance = appearance
        self.annotationDefaults = annotationDefaults
        self.showMagnifierWhileDragging = showMagnifierWhileDragging
    }

    /// A style assembled from defaults, so `MSAnnotate` never imports this module.
    public func annotationStyle() -> MSAnnotationStyleSpec {
        MSAnnotationStyleSpec(strokeHex: annotationDefaults.strokeHex,
                              lineWidth: annotationDefaults.lineWidth,
                              fontSize: annotationDefaults.fontSize,
                              blurRadius: annotationDefaults.blurRadius)
    }
}

/// Style carried across the settings→annotate boundary without creating a module dependency.
public struct MSAnnotationStyleSpec: Sendable, Equatable {
    public var strokeHex: String
    public var lineWidth: Int
    public var fontSize: Int
    public var blurRadius: Int
    public init(strokeHex: String, lineWidth: Int, fontSize: Int, blurRadius: Int) {
        self.strokeHex = strokeHex; self.lineWidth = lineWidth; self.fontSize = fontSize; self.blurRadius = blurRadius
    }
}

/// Reading surface used by every module that needs a preference.
public protocol MSReadingPreferences: Sendable {
    var current: MSAppPreferences { get }
}

public final class MSSettingsStore: MSReadingPreferences, @unchecked Sendable {
    private let defaultKey: String
    private let file: URL?
    private let lock = NSLock()
    private var cached: MSAppPreferences

    public init(userDefaultsKey: String = "com.macshot.prefs", directory: URL? = nil) {
        self.defaultKey = userDefaultsKey
        self.file = directory?.appendingPathComponent("preferences.json")
        if let file, let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(MSAppPreferences.self, from: data),
           decoded.schemaVersion <= MSAppPreferences.currentSchemaVersion {
            cached = decoded
            MSLog.info(.settings, "loaded schema=\(decoded.schemaVersion)")
        } else {
            cached = .init()
            MSLog.info(.settings, "using defaults")
        }
    }

    public var current: MSAppPreferences {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    public func update(_ mutate: (inout MSAppPreferences) -> Void) {
        lock.lock()
        var copy = cached
        mutate(&copy)
        copy.schemaVersion = MSAppPreferences.currentSchemaVersion
        cached = copy
        lock.unlock()
        persist(copy)
        MSLog.info(.settings, "updated commit=\(copy.commitBehavior.rawValue) format=\(copy.export.format.rawValue)")
    }

    /// Restore shipped defaults — used by the default-value test (`FR-SET-003`).
    public func resetToDefaults() {
        let fresh = MSAppPreferences()
        lock.lock(); cached = fresh; lock.unlock()
        persist(fresh)
    }

    private func persist(_ prefs: MSAppPreferences) {
        guard let file else { return }
        if let data = try? JSONEncoder.pretty.encode(prefs) {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                MSLog.error(.settings, "persist failed: \(error.localizedDescription)")
            }
        }
    }
}

extension JSONEncoder {
    /// Stable ordering keeps `git diff` readable if preferences ever end up in fixtures.
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
