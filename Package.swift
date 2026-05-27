// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Package: SynheartCore
// Version: 0.0.5
// License: Apache-2.0
// Description: Synheart Core SDK for iOS — Unified HSI-compatible data collection,
//              on-device state computation, and module orchestration.

import PackageDescription

let package = Package(
    name: "SynheartCore",
    platforms: [
        // iOS 16+ required by syni-swift (peer agent SDK). watchOS /
        // tvOS minimums unchanged — SyniSwift is gated to iOS / macOS
        // via the per-target `condition: .when(platforms: ...)` below.
        .iOS(.v16),
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
        .package(url: "https://github.com/synheart-ai/synheart-wear-swift", from: "0.4.1"),
        // synheart-emotion-swift and synheart-focus-swift removed —
        // emotion and focus are now computed by the native runtime
        // and accessed via RuntimeBridge.
        .package(url: "https://github.com/synheart-ai/synheart-behavior-swift", from: "0.4.0"),
        .package(url: "https://github.com/synheart-ai/synheart-session-swift", from: "0.2.1"),
        .package(url: "https://github.com/synheart-ai/synheart-auth-swift", from: "0.1.0"),
        // syni-swift dep intentionally omitted — SyniSwift has no tagged
        // release yet. SyniModule.swift is gated with `#if canImport(SyniSwift)`,
        // so the module compiles cleanly without the dep. To enable Syni in a
        // local workspace, swap this back in with a path/url ref.
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

