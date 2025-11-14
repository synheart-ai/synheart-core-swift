import Foundation

/// Conversation timing context
public struct ConversationContext: Codable {
    public let isInConversation: Bool
    public let conversationDuration: TimeInterval?
    public let lastInteractionTime: Date?
    
    public init(isInConversation: Bool = false,
                conversationDuration: TimeInterval? = nil,
                lastInteractionTime: Date? = nil) {
        self.isInConversation = isInConversation
        self.conversationDuration = conversationDuration
        self.lastInteractionTime = lastInteractionTime
    }
}

/// Device state context
public struct DeviceStateContext: Codable {
    public let isCharging: Bool
    public let batteryLevel: Float?
    public let isScreenOn: Bool
    public let networkType: String?
    
    public init(isCharging: Bool = false,
                batteryLevel: Float? = nil,
                isScreenOn: Bool = true,
                networkType: String? = nil) {
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel
        self.isScreenOn = isScreenOn
        self.networkType = networkType
    }
}

/// User patterns context
public struct UserPatternsContext: Codable {
    public let timeOfDay: TimeInterval
    public let dayOfWeek: Int
    public let activityPattern: String?
    
    public init(timeOfDay: TimeInterval = 0,
                dayOfWeek: Int = 0,
                activityPattern: String? = nil) {
        self.timeOfDay = timeOfDay
        self.dayOfWeek = dayOfWeek
        self.activityPattern = activityPattern
    }
}

/// Context state information
public struct ContextState: Codable {
    public let conversation: ConversationContext
    public let device: DeviceStateContext
    public let patterns: UserPatternsContext
    
    public init(conversation: ConversationContext = ConversationContext(),
                device: DeviceStateContext = DeviceStateContext(),
                patterns: UserPatternsContext = UserPatternsContext()) {
        self.conversation = conversation
        self.device = device
        self.patterns = patterns
    }
}

