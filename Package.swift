// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Package: SynheartCore
// Version: 1.2.0
// License: Apache-2.0
// Description: Synheart Core SDK for iOS — Unified HSI-compatible data collection,
//              on-device state computation, and module orchestration.

import PackageDescription

let package = Package(
    name: "SynheartCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "SynheartCore",
            targets: ["SynheartCore"]),
    ],
    dependencies: [
        .package(path: "../synheart-wear-swift"),
        // synheart-emotion-swift and synheart-focus-swift removed —
        // emotion and focus are now computed by the native runtime
        // and accessed via RuntimeBridge.
        .package(path: "../synheart-behavior-swift"),
        .package(path: "../synheart-session-swift"),
        .package(path: "../synheart-auth-swift"),
    ],
    targets: [
        .target(
            name: "SynheartCore",
            dependencies: [
                .product(name: "SynheartWear", package: "synheart-wear-swift"),
                .product(name: "SynheartBehavior", package: "synheart-behavior-swift",
                         condition: .when(platforms: [.iOS, .macOS])),
                .product(name: "SynheartSession", package: "synheart-session-swift"),
                .product(name: "SynheartAuth", package: "synheart-auth-swift"),
            ],
            path: "SynheartCore"),
        .testTarget(
            name: "SynheartCoreTests",
            dependencies: ["SynheartCore"],
            path: "Tests/SynheartCoreTests"),
    ]
)

