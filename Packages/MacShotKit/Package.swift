// swift-tools-version: 6.2
import PackageDescription

/// Names of the shipping modules, in dependency order (leaf first). This is the kit's public surface.
let kitModules: [String] = [
    "MSCore", "MSSettings", "MSHotKey", "MSCapture", "MSAnnotate",
    "MSOverlay", "MSPin", "MSExport", "MSSession",
]

let package = Package(
    name: "MacShotKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacShotKit", targets: kitModules),
        .library(name: "MacShotTestSupport", targets: ["MSTestSupport"]),
    ],
    targets: [
        .target(name: "MSCore", path: "Sources/MSCore"),

        .target(name: "MSSettings", dependencies: ["MSCore"], path: "Sources/MSSettings"),

        .target(name: "MSHotKey", dependencies: ["MSCore"], path: "Sources/MSHotKey"),

        .target(name: "MSCapture", dependencies: ["MSCore", "MSSettings"], path: "Sources/MSCapture"),

        .target(name: "MSAnnotate", dependencies: ["MSCore"], path: "Sources/MSAnnotate"),

        .target(name: "MSOverlay", dependencies: ["MSCore", "MSCapture", "MSAnnotate", "MSSettings"], path: "Sources/MSOverlay"),

        .target(name: "MSPin", dependencies: ["MSCore", "MSSettings", "MSAnnotate"], path: "Sources/MSPin"),

        .target(name: "MSExport", dependencies: ["MSCore", "MSAnnotate"], path: "Sources/MSExport"),

        .target(
            name: "MSSession",
            dependencies: ["MSCore", "MSCapture", "MSOverlay", "MSAnnotate", "MSPin", "MSExport", "MSHotKey", "MSSettings"],
            path: "Sources/MSSession"
        ),

        .target(
            name: "MSTestSupport",
            dependencies: ["MSCore", "MSCapture", "MSAnnotate", "MSSession"],
            path: "Sources/MSTestSupport"
        ),

        .testTarget(name: "MSCoreTests", dependencies: ["MSCore", "MSTestSupport"], path: "Tests/MSCoreTests"),
        .testTarget(name: "MSAnnotateTests", dependencies: ["MSAnnotate", "MSTestSupport"], path: "Tests/MSAnnotateTests"),
        .testTarget(name: "MSSessionTests", dependencies: ["MSSession", "MSSettings", "MSExport", "MSPin", "MSTestSupport"], path: "Tests/MSSessionTests"),
        .testTarget(name: "MSCaptureTests", dependencies: ["MSCapture", "MSTestSupport"], path: "Tests/MSCaptureTests"),
        .testTarget(name: "MSOverlayTests", dependencies: ["MSOverlay", "MSCore", "MSAnnotate", "MSTestSupport"], path: "Tests/MSOverlayTests"),
        .testTarget(name: "MSSettingsTests", dependencies: ["MSSettings", "MSExport", "MSTestSupport"], path: "Tests/MSSettingsTests"),
    ],
    swiftLanguageModes: [.v5]
)
