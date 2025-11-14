// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HSI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "HSI",
            targets: ["HSI"]),
    ],
    dependencies: [
        // Add dependencies here when needed
        // Example: .package(url: "https://github.com/synheart/synheart-emotion", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "HSI",
            dependencies: [],
            path: "HSI"),
        .testTarget(
            name: "HSITests",
            dependencies: ["HSI"],
            path: "Tests/HSITests"),
    ]
)

