import AppKit
import CryptoKit
import MSCore

/// 检查更新的**网络与界面**层（`ADR-023`）。
///
/// 全产品**只有这一个文件**允许出网，门禁按文件名放行（`check-style.sh` ③、`check-permissions.sh` ⑤）：
/// ① 只有用户点「检查更新…」才会走，没有任何自动/定时检查；
/// ② 只读公开清单与用户点过的那个资产链接，不发任何设备/用户标识（`NFR-029/030`）；
/// ③ 下载完**必须**校验 SHA-256 与清单一致才挂载；不一致就删文件并报错，绝不"试试看"。
@MainActor
enum MSUpdater {
    /// 一次检查的结果。UI 与探针都读它，免得两处各自解释。
    enum Outcome: Sendable {
        case upToDate(current: String, latest: String)
        case available(version: String, notes: String, asset: MSUpdateManifest.Asset, current: String)
        case noSource
        case networkFailure(String)
        case malformed(String)
    }

    private static let timeout: TimeInterval = 12

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// 拉清单并给出结论。这一段不碰 UI，所以探针能离线跑（`V-065`）。
    static func check(url: URL? = MSUpdateSource.manifestURL()) async -> Outcome {
        guard let url else { return .noSource }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .networkFailure("源返回 HTTP \(http.statusCode)")
            }
            let manifest = try JSONDecoder().decode(MSUpdateManifest.self, from: data)
            switch manifest.decide(current: currentVersion(), preferringExtension: "dmg") {
            case .upToDate(let current, let latest):
                return .upToDate(current: current, latest: latest)
            case .available(let asset, let latest, let current):
                return .available(version: latest, notes: manifest.notes, asset: asset, current: current)
            case .malformed(let why):
                return .malformed(why)
            }
        } catch let error as DecodingError {
            return .malformed("清单不是预期形状：\(error.localizedDescription)")
        } catch {
            return .networkFailure(error.localizedDescription)
        }
    }

    /// 下载 + 校验。**校验不过就删掉**，返回 nil 表示没拿到可信文件。
    /// 落地目录用导出默认目录（`~/Downloads`），与用户保存截图是同一个地方，好找。
    static func download(_ asset: MSUpdateManifest.Asset, into directory: URL) async -> URL? {
        guard let url = URL(string: asset.url) else { return nil }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                MSLog.error(.app, "update download http=\(http.statusCode)")
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            let bytes = (try? Data(contentsOf: temporary).count) ?? -1
            guard bytes == asset.bytes else {
                MSLog.error(.app, "update size mismatch got=\(bytes) expected=\(asset.bytes)")
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            let digest = try sha256(of: temporary)
            guard digest == asset.sha256.lowercased() else {
                // 校验和不符＝源被换过／传输被改／清单写错。删掉，不挂载，不打开。
                MSLog.error(.app, "update sha256 mismatch got=\(digest.prefix(12)) expected=\(asset.sha256.prefix(12))")
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(asset.name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            MSLog.info(.app, "update downloaded bytes=\(bytes) sha256=\(digest.prefix(12))…")
            return destination
        } catch {
            MSLog.error(.app, "update download failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// 分块算 SHA-256：包体是 MB 级，但接口不该假设它永远小。
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 用户点「检查更新…」的完整对话。返回 false 表示用户没往下走（稍后/关闭）。
    @discardableResult
    static func present(_ outcome: Outcome, directory: URL, over parent: NSWindow?) async -> Bool {
        switch outcome {
        case .upToDate(let current, let latest):
            info("已是最新版本", "当前 \(current)，源上最新 \(latest)。\n源：\(MSUpdateSource.defaultManifestURL)")
            return false
        case .noSource:
            info("没有可用的更新源", "更新地址没配置好（可用环境变量 MACSHOT_UPDATE_URL 指定清单）。")
            return false
        case .networkFailure(let why):
            info("检查更新失败", """
                 \(why)
                 如果这个仓库还没发布过任何 Release，源就是 404（发布用 `make release-bundle`）。
                 没有自动重试：想再查一次，点菜单「检查更新…」。
                 """)
            return false
        case .malformed(let why):
            info("更新清单读不懂", why)
            return false
        case .available(let version, let notes, let asset, let current):
            let alert = NSAlert()
            alert.messageText = "发现新版本 MacShot \(version)（当前 \(current)）"
            alert.informativeText = """
            \(notes.isEmpty ? "（源没写更新说明）" : notes)

            文件：\(asset.name)　大小：\(ByteCountFormatter.string(fromByteCount: Int64(asset.bytes), countStyle: .file))
            SHA-256：\(asset.sha256.prefix(16))…
            下载位置：\(directory.path)

            校验和一致才会挂载；不一致会直接删掉并报错。
            """
            alert.addButton(withTitle: "下载更新包")
            alert.addButton(withTitle: "复制下载链接")
            alert.addButton(withTitle: "稍后")
            let answer: NSApplication.ModalResponse
            if let parent { answer = await alert.beginSheetModal(for: parent) } else { answer = alert.runModal() }
            switch answer {
            case .alertFirstButtonReturn:
                guard let file = await download(asset, into: directory) else {
                    info("下载没成功", "文件已删除或没落盘。校验和不一致时不会挂载，这是有意的。")
                    return false
                }
                NSWorkspace.shared.open(file)      // 校验过了才交给系统挂载
                info("更新包已就绪", "\(file.path)\n在 Finder 里把 MacShot 拖进「应用程序」替换，然后重新打开即可。")
                return true
            case .alertSecondButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(asset.url, forType: .string)
                return false
            default:
                return false
            }
        }
    }

    /// 给日志与探针用的短标签：只含版本号与结论类型，不含 URL 参数、不含任何用户标识。
    static func describe(_ outcome: Outcome) -> String {
        switch outcome {
        case .upToDate(let current, let latest): return "upToDate current=\(current) latest=\(latest)"
        case .available(let version, _, let asset, let current): return "available \(current)→\(version) bytes=\(asset.bytes)"
        case .noSource: return "noSource"
        case .networkFailure: return "networkFailure"
        case .malformed: return "malformed"
        }
    }

    private static func info(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }
}
