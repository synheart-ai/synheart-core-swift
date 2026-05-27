// SPDX-License-Identifier: Apache-2.0
//
// High-level Swift wrapper around the native breathing compliance
// detector. Mirrors the Flutter / Kotlin references.
//
// All RR samples pushed via `CoreRuntimeBridge.pushRr` (i.e. Tier-1
// BLE chest-strap data) automatically feed the breathing detector.
// This module configures the target rate / population profile and
// reads back the current verdict. See RFC-Breathing-001 for the
// algorithm.

import Foundation

public final class BreathingModule {

    private let bridge: CoreRuntimeBridge

    public init(bridge: CoreRuntimeBridge) {
        self.bridge = bridge
    }

    /// Set the target breathing rate in breaths per minute
    /// (e.g. `6.0` for resonance breathing).
    public func setTargetBpm(_ bpm: Double) {
        bridge.breathingSetTargetBpm(bpm)
    }

    /// Set the rolling-window length in seconds. Native side clamps to `[30, 120]`.
    public func setWindowSecs(_ secs: Int) {
        bridge.breathingSetWindowSecs(secs)
    }

    /// Choose threshold profile (defaults to `.beginner`).
    public func setPopulation(_ profile: BreathingPopulation) {
        bridge.breathingSetPopulation(profile.rawValue)
    }

    /// Compute compliance for the current RR window. Returns
    /// `.insufficient` when there isn't enough Tier-1 data yet.
    public func evaluate() -> BreathingComplianceResult {
        guard let json = bridge.breathingEvaluateJson() else {
            return .insufficient(reason: .notEnoughBeats(have: 0, need: 50))
        }
        do {
            return try BreathingComplianceResult.fromJsonString(json)
        } catch {
            return .insufficient(reason: .notEnoughBeats(have: 0, need: 50))
        }
    }

    /// Clear the RR ring buffer. Call when starting a new breathing exercise.
    public func reset() {
        bridge.breathingReset()
    }
}
