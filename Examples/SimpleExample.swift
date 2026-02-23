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

        // Initialize with wearable data collection
        try await Synheart.initialize(
            userId: "user_123",
            config: SynheartConfig(
                allowUnsignedCapabilities: true,
                enableWear: true
            )
        )

        // Grant consent for biosignal collection
        try await Synheart.grantConsent("biosignals")

        // Subscribe to HSI updates
        Synheart.onHSIUpdate
            .sink { hsi in
                print("Arousal: \(hsi.affect?.arousalIndex ?? 0)")
                print("Valence: \(hsi.affect?.valenceIndex ?? 0)")
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
