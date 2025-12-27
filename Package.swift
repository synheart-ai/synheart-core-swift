// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SynheartCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "SynheartCore",
            targets: ["SynheartCore"]),
    ],
    dependencies: [
        // Add dependencies here when needed
        // Example: .package(url: "https://github.com/synheart/synheart-emotion", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SynheartCore",
            dependencies: [],
            path: "SynheartCore"),
        .testTarget(
            name: "SynheartCoreTests",
            dependencies: ["SynheartCore"],
            path: "Tests/SynheartCoreTests"),
    ]
)

