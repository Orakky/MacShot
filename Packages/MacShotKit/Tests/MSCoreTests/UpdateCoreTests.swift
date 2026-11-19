import Foundation
import Testing
@testable import MSCore

/// 检查更新的**纯逻辑**判据（`V-064`）。这里一条都不联网：网络与 UI 在 `App/MSUpdater.swift`，
/// 判据要能离线跑，否则门禁就成了"看网络脸色"。
struct UpdateCoreTests {
    private let sum64 = String(repeating: "a", count: 64)

    private var dmg: MSUpdateManifest.Asset {
        MSUpdateManifest.Asset(name: "MacShot-0.2.0.dmg",
                               url: "https://github.com/Orakky/MacShot/releases/download/v0.2.0/MacShot-0.2.0.dmg",
                               sha256: sum64, bytes: 1_700_000)
    }
    private func manifest(_ version: String, _ assets: [MSUpdateManifest.Asset] = [], notes: String = "") -> MSUpdateManifest {
        MSUpdateManifest(version: version, notes: notes, assets: assets)
    }

    @Test("版本号比较：补零对齐，`0.2`==`0.2.0`、`0.10.0`>`0.9.0`（比字符串会判反）")
    func versionOrdering() throws {
        let v = try #require(MSVersion("0.2"))
        #expect(v == MSVersion("0.2.0"))
        #expect(try #require(MSVersion("0.10.0")) > #require(MSVersion("0.9.0")))
        #expect(MSVersion("v1.2.3") == MSVersion("1.2.3"), "前缀 v 要吃得下")
        #expect(MSVersion("0.2.0-beta") == MSVersion("0.2.0"), "尾巴上的预发布标记忽略，不当成更新")
        #expect(try #require(MSVersion("0.2.0")) < #require(MSVersion("0.2.1")))
        #expect(MSVersion("abc") == nil && MSVersion("") == nil)
        #expect(MSVersion("0.2.0")?.description == "0.2.0")
    }

    @Test("结论分类：相等、源比本机旧，都不许报「有新版」")
    func decisions() {
        #expect(manifest("0.1.0").decide(current: "0.1.0") == .upToDate(current: "0.1.0", latest: "0.1.0"))
        #expect(manifest("0.1.0", [dmg]).decide(current: "0.2.0").isUpToDate, "源比本机旧＝没更新，不许催")
        #expect(manifest("0.2.0", [dmg]).decide(current: "0.2").isUpToDate, "0.2 与 0.2.0 是同一个版本")
        if case .available(let asset, let latest, let current) = manifest("0.2.0", [dmg], notes: "修了两条").decide(current: "0.1.0") {
            #expect(asset.name == "MacShot-0.2.0.dmg" && latest == "0.2.0" && current == "0.1.0")
        } else {
            Issue.record("有新版却没给出资产")
        }
    }

    @Test("清单坏了必须明说：校验和不是 64 位十六进制、字节数不合法、没有资产、版本读不懂")
    func malformedIsExplicit() {
        let short = MSUpdateManifest.Asset(name: "x.dmg", url: "https://e/x.dmg", sha256: "abc", bytes: 10)
        let spacey = MSUpdateManifest.Asset(name: "x.dmg", url: "https://e/x.dmg",
                                            sha256: String(repeating: "a", count: 63) + " ", bytes: 10)
        let zeroBytes = MSUpdateManifest.Asset(name: "x.dmg", url: "https://e/x.dmg",
                                               sha256: String(repeating: "f", count: 64), bytes: 0)
        #expect(manifest("0.2.0", [short]).decide(current: "0.1.0").isMalformed,
                "校验和短一截也算合法的话，验证就白做了")
        #expect(manifest("0.2.0", [spacey]).decide(current: "0.1.0").isMalformed)
        #expect(manifest("0.2.0", [zeroBytes]).decide(current: "0.1.0").isMalformed)
        #expect(manifest("0.2.0", []).decide(current: "0.1.0").isMalformed, "没有资产就别装作能更新")
        #expect(manifest("nightly").decide(current: "0.1.0").isMalformed)
    }

    @Test("优先挑 .dmg 资产；只有 zip 时兜底，而不是报清单坏")
    func prefersDmgAsset() throws {
        let zip = MSUpdateManifest.Asset(name: "MacShot.zip", url: "https://e/MacShot.zip",
                                         sha256: String(repeating: "b", count: 64), bytes: 500)
        if case .available(let picked, _, _) = manifest("0.2.0", [zip, dmg]).decide(current: "0.1.0") {
            #expect(picked.url.hasSuffix(".dmg"), "got=\(picked.name)")
        } else {
            Issue.record("该判成 available")
        }
        if case .available(let onlyZip, _, _) = manifest("0.2.0", [zip]).decide(current: "0.1.0") {
            #expect(onlyZip.name == "MacShot.zip", "没有 dmg 时要能退回 zip")
        } else {
            Issue.record("兜底没生效")
        }
    }

    @Test("默认源是 GitHub Releases 的公开路径；环境变量可覆盖（判据与自建源都靠它）")
    func sourceURL() throws {
        let url = try #require(MSUpdateSource.manifestURL(environment: [:]))
        #expect(url.absoluteString == "https://github.com/Orakky/MacShot/releases/latest/download/latest.json")
        #expect(url.absoluteString.hasPrefix("https://"), "更新源必须走 HTTPS（`ADR-023` 的完整性前提）")
        #expect(!url.absoluteString.contains("api.github.com"),
                "用公开下载路径，不用 API：免 token、免速率限制")
        let overridden = try #require(MSUpdateSource.manifestURL(environment: ["MACSHOT_UPDATE_URL": "file:///tmp/latest.json"]))
        #expect(overridden.scheme == "file", "测试与自建源要能指到本地文件，否则判据只能靠联网")
    }

    @Test("清单 JSON 解码：字段缺一个就该失败，不许猜默认值")
    func manifestDecoding() throws {
        let good = "{\"version\":\"0.2.0\",\"notes\":\"修了两条\",\"assets\":[{\"name\":\"a.dmg\","
                 + "\"url\":\"https://e/a.dmg\",\"sha256\":\"\(String(repeating: "0", count: 64))\",\"bytes\":10}]}"
        let decoded = try JSONDecoder().decode(MSUpdateManifest.self, from: Data(good.utf8))
        #expect(decoded.version == "0.2.0" && decoded.assets.count == 1 && decoded.assets[0].bytes == 10)
        let missingNotes = Data("{\"version\":\"0.2.0\",\"assets\":[]}".utf8)
        let attempt = try? JSONDecoder().decode(MSUpdateManifest.self, from: missingNotes)
        #expect(attempt == nil, "notes 缺失时静默补空串，会把「没有更新说明」看成「说明是空」")
    }
}

private extension MSUpdateManifest.Decision {
    var isUpToDate: Bool { if case .upToDate = self { return true }; return false }
    var isMalformed: Bool { if case .malformed = self { return true }; return false }
}
