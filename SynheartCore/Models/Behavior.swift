import Foundation

/// Behavioral metrics state
public struct BehaviorState: Codable {
    /// Typing speed (normalized 0.0 - 1.0)
    public let typingSpeed: Float?

    /// Typing burstiness (0.0 - 1.0)
    public let typingBurstiness: Float?

    /// Scroll velocity (normalized 0.0 - 1.0)
    public let scrollVelocity: Float?

    /// Idle gaps between interactions (seconds)
    public let idleGaps: Float?

    /// App switch rate (normalized)
    public let appSwitchRate: Float?

    /// Interaction intensity (normalized 0.0 - 1.0)
    public let interactionIntensity: Float?

    /// Engagement level (normalized 0.0 - 1.0)
    public let engagementLevel: Float?

    public init(typingSpeed: Float? = nil,
                typingBurstiness: Float? = nil,
                scrollVelocity: Float? = nil,
                idleGaps: Float? = nil,
                appSwitchRate: Float? = nil,
                interactionIntensity: Float? = nil,
                engagementLevel: Float? = nil) {
        self.typingSpeed = typingSpeed
        self.typingBurstiness = typingBurstiness
        self.scrollVelocity = scrollVelocity
        self.idleGaps = idleGaps
        self.appSwitchRate = appSwitchRate
        self.interactionIntensity = interactionIntensity
        self.engagementLevel = engagementLevel
    }
}
