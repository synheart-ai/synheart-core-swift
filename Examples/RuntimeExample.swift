// RuntimeExample.swift
// Synheart Core SDK — Runtime integration example
//
// Demonstrates end-to-end runtime integration:
// 1. SDK initialization
// 2. Runtime version check and diagnostics
// 3. Consent granting
// 4. Session start with HSI subscription + internal diagnostics
// 5. Pre-processed data access (internal — R&D / training)
// 6. Runtime diagnostics logging
//
// Run with:
//   DYLD_LIBRARY_PATH=./lib swift run RuntimeExample
//
// For a minimal example, see SimpleExample.swift.
// For a full-featured example, see CanonicalExample.swift.

import Foundation
import Combine
import SynheartCore

@main
struct RuntimeExample {
    static func main() async throws {
        var cancellables = Set<AnyCancellable>()

        // 1. Check runtime availability before initializing
        let runtimeVersion = RuntimeBridge.version()
        print("[Runtime] Version: \(runtimeVersion ?? "unavailable")")
        print("[Runtime] Native library loaded: \(runtimeVersion != nil)")

        // 2. Initialize SDK with all modules enabled
        try await Synheart.initialize(
            userId: "runtime_example_user",
            config: SynheartConfig(
                allowUnsignedCapabilities: true,
                enableWear: true,
                enablePhone: true,
                enableBehavior: true
            )
        )
        print("[Synheart] SDK initialized")

        // 3. Grant consent for all data types
        try await Synheart.grantConsent("biosignals")
        try await Synheart.grantConsent("behavior")
        try await Synheart.grantConsent("phoneContext")
        print("[Synheart] Consent granted for biosignals, behavior, phoneContext")

        // 4. Subscribe to HSI updates with runtime diagnostics
        var frameCounter = 0
        Synheart.onHSIUpdate
            .sink { hsi in
                frameCounter += 1
                print("[HSI] Frame #\(frameCounter) received (\(hsi.prefix(80))...)")

                // Log runtime diagnostics periodically
                if frameCounter % 5 == 0 {
                    print("[Runtime] Diagnostics after \(frameCounter) frames:")
                    print("  Version: \(RuntimeBridge.version() ?? "N/A")")
                }
            }
            .store(in: &cancellables)

        // 5. Pre-processed data access (internal — R&D / training)
        // This demonstrates accessing intermediate signal processing outputs
        print("\n[Runtime] Pre-processed data access example:")
        if let runtimeModule = Synheart.runtimeModule(),
           let bridge = runtimeModule.bridge,
           let json = bridge.lastPreprocessed() {
            if let window = try? PreprocessedWindow.fromJson(json) {
                print("  Quality score: \(window.quality.score)")
                if let hrv = window.derivedFeatures.hrv {
                    print("  HRV RMSSD: \(hrv.rmssdMs)ms")
                }
                print("  Embeddings dimension: \(window.embeddings.signalEmbedding.dimension)")
                print("  SRM ready count: \(window.srmContext.readyCount)/\(window.srmContext.totalCount)")
            }
        }

        // 6. Start session — data collection begins
        try await Synheart.startSession()
        print("[Synheart] Session started")
        print("[Synheart] Active features: \(Synheart.activatedFeatures())")

        // 6. Run for 30 seconds
        print("[Synheart] Running for 30 seconds...")
        try await Task.sleep(nanoseconds: 30_000_000_000)

        // 7. Final diagnostics
        print("\n[Runtime] Final diagnostics:")
        print("  Version: \(RuntimeBridge.version() ?? "N/A")")
        print("  Total HSI frames received: \(frameCounter)")

        // 8. Clean shutdown
        try await Synheart.stopSession()
        try await Synheart.dispose()
        print("[Synheart] SDK disposed")
    }
}
