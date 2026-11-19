import Foundation
import MSCore

/// All persisted preferences in one value type with a schema version. Fields are append-only:
/// renaming or re-purposing one is a schema break, not a refactor (`FR-SET-003`, `ADR-009` style).
public struct MSAppPreferences: Codable, Sendable, Equatable {
    /// 5 = 导出默认目录改到 **下载**（`~/Downloads`，用户 11-19）。同 v4 的教训：光翻默认值对
    /// 老用户无效——每次写盘都把整份结构体连默认值 materialize 落盘，所以旧文件里那句
    /// `~/Pictures/MacShot` 也不是用户选过的路径 ⇒ 见 `legacyExportDirectories` 的定向迁移。
    /// 4 = `showMagnifierWhileDragging` 默认改 `false`（用户 2026-11-18 改判 Q-07：截图时不要
    /// 那个自动弹出的额外画面）。**默认值变了、字段没变**，所以旧文件里显式存过 `true` 的人
    /// 仍是 `true`——schema 不必升；这里升号只为了给"默认档变了"留一个可对账的记录点。
    /// 3 = 删掉 `confirmBeforeDiscardingUnexportedPins`：`Q-06` 已裁"退出直接抛弃、不加确认"，
    /// 这个字段的需求前提被推翻了，留着就是"有开关、没行为"（`B-037` / `E-070`）。
    /// 2 = 剪贴板不再双写 TIFF（`Q-04`），删掉 `Export.writesPngAndTiffToPasteboard`。
    /// 读侧允许 `schemaVersion <= current`（§114），旧文件里多出来的那个键会被忽略，
    /// 所以这是一次**向前兼容**的收窄，不是迁移。
    public static let currentSchemaVersion = 5

    /// 历史上当过默认值、但**从未被用户主动选过**的导出目录。`schemaVersion < 5` 的文件里
    /// 出现这些字符串＝旧默认被 materialize 下来的，迁移回落到现默认；
    /// 用户自己填的路径（不在这个表里）一律不动。
    public static let legacyExportDirectories = ["~/Pictures/MacShot"]

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
        public static let standard = Export(directory: "~/Downloads",
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

        /// 工具条动作格用的短动词。与 `label` 分开是因为条里给动作文字只预留了
        /// `MSAnnotationToolbar.actionWidth = 250pt`，"保存到文件"四个汉字会把四段文字撑到 262pt
        /// 挤到色板上（几何单测 `ToolbarGeometryTests` 钉住这条）。菜单与设置窗仍用 `label`。
        public var shortLabel: String {
            switch self { case .pin: "贴出"; case .copy: "复制"; case .save: "保存" }
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
                showMagnifierWhileDragging: Bool = false) {
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
            // **低于 4 的文件里这个字段不是用户的选择**：当时设置窗还没有这个开关，而每次
            // `update()` 都会把整份结构体连默认值一起 materialize 落盘 ⇒ 读到的 `true` 只是旧默认。
            // 照读的话，11-18 翻过来的新默认永远到不了用户屏幕上（实测：这台机器的
            // `preferences.json` 是 schema 2、里面就写着 `showMagnifierWhileDragging: true`）。
            // 钉死在 4，不能写 `< currentSchemaVersion`：schema 再往上走（v5＝导出目录）时，
            // 那条规则会把 **v4 里用户真点过的开关**也当成旧默认擦掉。
            if decoded.schemaVersion < 4,
               cached.showMagnifierWhileDragging != MSAppPreferences().showMagnifierWhileDragging {
                MSLog.info(.settings, "schema \(decoded.schemaVersion) 的放大镜字段按旧默认落盘，回落到出厂默认")
                cached.showMagnifierWhileDragging = MSAppPreferences().showMagnifierWhileDragging
            }
            // 导出目录的迁移必须**认值**：旧文件里既可能是被 materialize 的旧默认，也可能是
            // 用户自己填的路径，两者不能一概而论。只有等于历史默认的那条才回落。
            let storedDirectory = cached.export.directory
            if decoded.schemaVersion < 5, MSAppPreferences.legacyExportDirectories.contains(storedDirectory) {
                let shipped = MSAppPreferences().export.directory
                MSLog.info(.settings, "schema \(decoded.schemaVersion) 的导出目录是旧默认 \(storedDirectory)，回落到 \(shipped)")
                cached.export.directory = shipped
            }
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
