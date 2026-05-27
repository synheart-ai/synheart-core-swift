import Foundation

/// Types of behavior events
public enum BehaviorEventType {
    case tap
    case scroll
    case keyDown
    case keyUp
    case appSwitch
    case notificationReceived
    case notificationOpened
}

/// Behavior event captured from user interactions
public struct BehaviorEvent {
    public let type: BehaviorEventType
    public let timestamp: Date
    public let metadata: [String: Any]?
    
    public init(type: BehaviorEventType, timestamp: Date, metadata: [String: Any]? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
    
    public static func tap(x: Double, y: Double) -> BehaviorEvent {
        return BehaviorEvent(
            type: .tap,
            timestamp: Date(),
            metadata: ["x": x, "y": y]
        )
    }
    
    public static func scroll(delta: Double) -> BehaviorEvent {
        return BehaviorEvent(
            type: .scroll,
            timestamp: Date(),
            metadata: ["delta": delta]
        )
    }
    
    public static func keyDown() -> BehaviorEvent {
        return BehaviorEvent(
            type: .keyDown,
            timestamp: Date()
        )
    }
    
    public static func keyUp() -> BehaviorEvent {
        return BehaviorEvent(
            type: .keyUp,
            timestamp: Date()
        )
    }
    
    public static func appSwitch() -> BehaviorEvent {
        return BehaviorEvent(
            type: .appSwitch,
            timestamp: Date()
        )
    }
    
    public static func notificationReceived() -> BehaviorEvent {
        return BehaviorEvent(
            type: .notificationReceived,
            timestamp: Date()
        )
    }
    
    public static func notificationOpened() -> BehaviorEvent {
        return BehaviorEvent(
            type: .notificationOpened,
            timestamp: Date()
        )
    }
}

