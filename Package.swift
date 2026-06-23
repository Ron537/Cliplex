// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cliplex",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        // Testable, UI-independent core: storage, models, clipboard capture,
        // paste injection, and permissions.
        .target(
            name: "CliplexKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/CliplexKit"
        ),
        // The menu-bar agent app (AppKit shell + SwiftUI content).
        .executableTarget(
            name: "Cliplex",
            dependencies: ["CliplexKit"],
            path: "Sources/Cliplex"
        ),
        .testTarget(
            name: "CliplexKitTests",
            dependencies: ["CliplexKit"],
            path: "Tests/CliplexKitTests"
        )
    ]
)
