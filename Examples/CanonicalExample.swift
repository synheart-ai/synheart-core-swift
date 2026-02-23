// CanonicalExample.swift
// Synheart Core SDK — Full-featured example
//
// This example demonstrates the complete SDK surface:
// 1. Initialization with full module configuration
// 2. Consent management for all data types
// 3. HSI streaming (core state representation)
// 4. Activating optional features (Focus, Emotion)
// 5. Feature activation/deactivation
// 6. Error handling
// 7. Clean shutdown
//
// For a minimal example, see SimpleExample.swift.

import Foundation
import Combine
import SynheartCore

@main
struct CanonicalExample {
    static func main() async throws {
        var cancellables = Set<AnyCancellable>()

        // 1. Initialize SDK with all modules enabled
        //    In production, replace allowUnsignedCapabilities with
        //    capabilityToken + capabilitySecret from your server.
        do {
            try await Synheart.initialize(
                userId: "example_user_123",
                config: SynheartConfig(
                    allowUnsignedCapabilities: true,
                    enableWear: true,
                    enablePhone: true,
                    enableBehavior: true
                )
            )
            print("[Synheart] SDK initialized")
        } catch SynheartError.capabilityTokenRequired {
            print("[Synheart] Error: Capability token required in production mode")
            return
        } catch {
            print("[Synheart] Initialization failed: \(error)")
            return
        }

        // 2. Grant consent for all data collection types
        try await Synheart.grantConsent("biosignals")
        try await Synheart.grantConsent("behavior")
        try await Synheart.grantConsent("phoneContext")
        print("[Synheart] Consent granted for biosignals, behavior, phoneContext")

        // 3. Subscribe to HSI updates (core state representation)
        Synheart.onHSIUpdate
            .sink { hsi in
                print("[HSI] v\(hsi.hsiVersion) at \(hsi.observedAtUtc ?? "unknown")")
            }
            .store(in: &cancellables)

        // 4. Activate optional features (four-authority model)
        //    Features become operational when: Activated AND Consent AND Capability AND SessionActive
        Synheart.activate(.focus)
        Synheart.onFocusUpdate
            .sink { focus in
                print("[Focus] Score: \(focus.score)")
            }
            .store(in: &cancellables)

        Synheart.activate(.emotion)
        Synheart.onEmotionUpdate
            .sink { emotion in
                print("[Emotion] Stress: \(emotion.stress)")
            }
            .store(in: &cancellables)

        // 5. Start session — data collection begins, activated features become operational
        try await Synheart.startSession()
        print("[Synheart] Session started")
        print("[Synheart] Active features: \(Synheart.activatedFeatures())")

        // Run for 30 seconds as a demo
        try await Task.sleep(nanoseconds: 30_000_000_000)

        // 6. Features can be deactivated mid-session
        Synheart.deactivate(.emotion)
        print("[Synheart] Emotion deactivated")

        // 7. Consent can be revoked mid-session — affected features stop automatically
        // try await Synheart.revokeConsent("behavior")

        // 8. Clean shutdown
        try await Synheart.stopSession()
        try await Synheart.dispose()
        print("[Synheart] SDK disposed")
    }
}
