// CanonicalExample.swift
// Synheart Core SDK — Full-featured example
//
// This example demonstrates the complete SDK surface:
// 1. Configuration with SynheartConfig
// 2. Consent management for all data types
// 3. Typed state streaming via onStateUpdate
// 4. Feature activation/deactivation (four-authority model)
// 5. Session lifecycle (start/stop)
// 6. Sync API
// 7. Error handling
// 8. Clean shutdown
//
// For a minimal example, see SimpleExample.swift.

import Foundation
import Combine
import SynheartCore

@main
struct CanonicalExample {
    static func main() async throws {
        var cancellables = Set<AnyCancellable>()

        // 1. Configure SDK
        //    In production, replace allowUnsignedCapabilities with
        //    capabilityToken + capabilitySecret from your server.
        do {
            try await Synheart.configure(config: SynheartConfig(
                appId: "com.example.app",
                subjectId: "example_user_123",
                allowUnsignedCapabilities: true
            ))
            print("[Synheart] SDK configured")
        } catch SynheartError.capabilityTokenRequired {
            print("[Synheart] Error: Capability token required in production mode")
            return
        } catch {
            print("[Synheart] Configuration failed: \(error)")
            return
        }

        // 2. Grant consent for all data collection types
        try await Synheart.grantConsent("biosignals")
        try await Synheart.grantConsent("behavior")
        try await Synheart.grantConsent("phoneContext")
        print("[Synheart] Consent granted for biosignals, behavior, phoneContext")

        // 3. Subscribe to typed state updates
        Synheart.onStateUpdate
            .sink { state in
                print("[State] \(state)")
            }
            .store(in: &cancellables)

        // 4. Activate features (four-authority model)
        //    Features become operational when: Activated AND Consent AND Capability AND SessionActive
        Synheart.activate(.wear)
        Synheart.activate(.behavior)
        Synheart.activate(.phoneContext)

        // 5. Start session — data collection begins, activated features become operational
        try await Synheart.startSession()
        print("[Synheart] Session started")
        print("[Synheart] Active features: \(Synheart.activatedFeatures())")

        // Run for 30 seconds as a demo
        try await Task.sleep(nanoseconds: 30_000_000_000)

        // 6. Features can be deactivated mid-session
        Synheart.deactivate(.behavior)
        print("[Synheart] Behavior deactivated")

        // 7. Consent can be revoked mid-session — affected features stop automatically
        // try await Synheart.revokeConsent("behavior")

        // 8. Sync data before shutdown
        let result = try await Synheart.syncNow()
        print("[Synheart] Sync result: \(result)")

        // 9. Clean shutdown
        try await Synheart.stopSession()
        try await Synheart.dispose()
        print("[Synheart] SDK disposed")
    }
}
