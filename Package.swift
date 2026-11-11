// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProZip",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ProZipShared", targets: ["ProZipShared"]),
        .library(name: "ProZipCore", targets: ["ProZipCore"]),
        .library(name: "ProZipEngines", targets: ["ProZipEngines"]),
        .library(name: "ProZipUI", targets: ["ProZipUI"]),
        .executable(name: "ProZip", targets: ["ProZipApp"]),
        .executable(name: "ProZipFinderSync", targets: ["ProZipFinderSync"]),
        .executable(name: "ProZipQuickLook", targets: ["ProZipQuickLook"])
    ],
    targets: [
        .target(
            name: "ProZipShared",
            dependencies: [],
            path: "Sources/ProZipShared"
        ),
        .target(
            name: "ProZipCore",
            dependencies: ["ProZipShared"],
            path: "Sources/ProZipCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication")
            ]
        ),
        .target(
            name: "ProZipEngines",
            dependencies: ["ProZipShared", "ProZipCore"],
            path: "Sources/ProZipEngines",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedFramework("CoreText"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "ProZipUI",
            dependencies: ["ProZipShared", "ProZipCore", "ProZipEngines"],
            path: "Sources/ProZipUI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("AVKit")
            ]
        ),
        .executableTarget(
            name: "ProZipApp",
            dependencies: ["ProZipShared", "ProZipCore", "ProZipEngines", "ProZipUI"],
            path: "Sources/ProZipApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("FinderSync")
            ]
        ),
        .executableTarget(
            name: "ProZipFinderSync",
            dependencies: ["ProZipShared"],
            path: "Sources/ProZipFinderSync",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("FinderSync"),
                .linkedFramework("Foundation"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])
            ]
        ),
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        .executableTarget(
            name: "ProZipQuickLook",
            dependencies: ["CArchive"],
            path: "Sources/ProZipQuickLook",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Foundation"),
                .linkedLibrary("archive"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])
            ]
        ),
        .testTarget(
            name: "ProZipFinderSyncTests",
            dependencies: ["ProZipFinderSync", "ProZipShared"],
            path: "Tests/ProZipFinderSyncTests"
        ),
        .testTarget(
            name: "ProZipQuickLookTests",
            dependencies: ["ProZipQuickLook", "CArchive", "ProZipShared"],
            path: "Tests/ProZipQuickLookTests"
        ),
        .testTarget(
            name: "ProZipTests",
            dependencies: ["ProZipShared", "ProZipCore", "ProZipEngines", "ProZipUI"],
            path: "Tests/ProZipTests"
        )
    ]
)
