// SPDX-License-Identifier: Apache-2.0
//
// Default user-facing copy for `NonComplianceReason`. The native engine
// emits structured reasons (frequency mismatch, shallow breathing, etc.).
// Wording belongs to the consumer; this file ships a neutral default so
// most apps can stay one-liner. Apps wanting a different tone can swap
// in their own localizer via `BreathingGuidanceCopy.localize`.

import Foundation

/// Single-line coaching string for a `NonComplianceReason`. Pure
/// function; no engine call.
public typealias BreathingGuidanceLocalizer = @Sendable (NonComplianceReason) -> String

public enum BreathingGuidanceCopy {
    /// Default-tone English. Override via [localize] to swap in your own
    /// copy globally without forking call sites.
    nonisolated(unsafe) public static var localize: BreathingGuidanceLocalizer = defaultEn

    /// Convenience equivalent of `localize(reason)`.
    public static func copyFor(_ reason: NonComplianceReason) -> String {
        return localize(reason)
    }

    @Sendable
    static func defaultEn(_ reason: NonComplianceReason) -> String {
        switch reason {
        case let .wrongFrequency(detectedBpm, targetBpm):
            return detectedBpm > targetBpm
                ? "Slow down - you're breathing faster than the target."
                : "Speed up slightly - you're breathing slower than the target."
        case .shallowBreathing:
            return "Good rhythm - now breathe deeper, take fuller breaths."
        case .irregularPattern:
            return "Try to keep a steady, even rhythm with the pacer."
        case .noBreathingSignature:
            return "We can't detect a breathing pattern yet - follow the pacer."
        }
    }
}
