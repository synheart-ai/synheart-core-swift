// SimpleExample.swift
// Synheart Core SDK — Minimal example
//
// The absolute minimum to get HSI data flowing.
// For a full-featured example, see CanonicalExample.swift.

import Foundation
import Combine
import SynheartCore

@main
struct SimpleExample {
    static func main() async throws {
        var cancellables = Set<AnyCancellable>()

        // Configure with wearable data collection
        try await Synheart.configure(config: SynheartConfig(
            appId: "com.example.app",
            subjectId: "user_123",
            allowUnsignedCapabilities: true
        ))

        // Grant consent for biosignal collection
        try await Synheart.grantConsent("biosignals")

        // Subscribe to typed state updates
        Synheart.onStateUpdate
            .sink { state in
                print("State: \(state)")
            }
            .store(in: &cancellables)

        // Start session — data collection begins
        try await Synheart.startSession()
        print("Session started")

        // Run for 30 seconds
        try await Task.sleep(nanoseconds: 30_000_000_000)

        // Clean up
        try await Synheart.stopSession()
        try await Synheart.dispose()
    }
}
