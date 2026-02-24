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

        // Subscribe to HSI updates (JSON string from synheart-runtime)
        Synheart.onHSIUpdate
            .sink { hsiJson in
                guard let data = hsiJson.data(using: .utf8),
                      let hsi = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                if let affect = hsi["affect"] as? [String: Any] {
                    print("Arousal: \(affect["arousal_index"] ?? 0)")
                    print("Valence: \(affect["valence_index"] ?? 0)")
                }
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
