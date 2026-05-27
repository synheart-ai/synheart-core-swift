import Foundation
import Combine

/// Conversation timing context
public struct ConversationContext: Codable {
    /// Whether a conversation is currently active
    public let isActive: Bool

    /// Average reply delay in seconds
    public let avgReplyDelaySec: Double?

    /// Number of messages in conversation
    public let messageCount: Int?

    /// Burstiness of conversation (0.0 - 1.0)
    public let burstiness: Double?

    public init(isActive: Bool = false,
                avgReplyDelaySec: Double? = nil,
                messageCount: Int? = nil,
                burstiness: Double? = nil) {
        self.isActive = isActive
        self.avgReplyDelaySec = avgReplyDelaySec
        self.messageCount = messageCount
        self.burstiness = burstiness
    }
}

/// Device state context
public struct DeviceStateContext: Codable {
    /// Whether screen is on
    public let screenOn: Bool

    /// Whether device is charging
    public let isCharging: Bool

    /// Battery level (0.0 - 1.0)
    public let batteryLevel: Float?

    /// Network type (e.g., "wifi", "cellular")
    public let networkType: String?

    /// Focus mode (e.g., "work", "personal", "none")
    public let focusMode: String?

    public init(screenOn: Bool = true,
                isCharging: Bool = false,
                batteryLevel: Float? = nil,
                networkType: String? = nil,
                focusMode: String? = nil) {
        self.screenOn = screenOn
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel
        self.networkType = networkType
        self.focusMode = focusMode
    }
}

/// User patterns context
public struct UserPatternsContext: Codable {
    /// Time of day in seconds since midnight
    public let timeOfDay: Double

    /// Day of week (0-6, 0=Sunday)
    public let dayOfWeek: Int

    /// Average session length in minutes
    public let avgSessionMinutes: Double?

    /// Activity pattern (e.g., "work", "exercise", "rest")
    public let activityPattern: String?

    public init(timeOfDay: Double = 0,
                dayOfWeek: Int = 0,
                avgSessionMinutes: Double? = nil,
                activityPattern: String? = nil) {
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.avgSessionMinutes = avgSessionMinutes
        self.activityPattern = activityPattern
    }
}

/// Context state information
public struct ContextState: Codable {
    /// Conversation timing metrics
    public let conversation: ConversationContext?

    /// Device state information
    public let device: DeviceStateContext?

    /// User pattern information
    public let userPatterns: UserPatternsContext?

    public init(conversation: ConversationContext? = nil,
                device: DeviceStateContext? = nil,
                userPatterns: UserPatternsContext? = nil) {
        self.conversation = conversation
        self.device = device
        self.userPatterns = userPatterns
    }
}
