import Foundation

/// Stable event codes accepted by `synheart_core_push_behavior`.
public enum RuntimeBehaviorEvent: Int32, Sendable {
    case screenOn = 0
    case screenOff = 1
    case input = 2
    case appSwitch = 3
    case notification = 4
    case scroll = 5
    case swipe = 6
    case call = 7
}

protocol BehaviorRuntimeSinking: AnyObject {
    func pushBehavior(tsMs: Int64, eventType: Int32, value: Double)
}

extension SynheartCoreShim: BehaviorRuntimeSinking {}

protocol BehaviorCollecting: AnyObject {
    var onEvent: ((BehaviorEvent) -> Void)? { get set }
    func start(sessionId: String?) throws
    func stop()
}

func makeProductionBehaviorCollector() -> (any BehaviorCollecting)? {
    #if canImport(SynheartBehavior)
    return SynheartBehaviorCollector()
    #else
    return nil
    #endif
}

enum BehaviorRuntimeMapping {
    static func map(_ event: BehaviorEvent) -> (RuntimeBehaviorEvent, Double)? {
        switch event.type {
        case .tap, .keyDown, .keyUp:
            return (.input, 1)
        case .appSwitch:
            return (.appSwitch, 1)
        case .notificationReceived, .notificationOpened:
            return (.notification, 1)
        case .scroll:
            return (.scroll, number(event.metadata?["delta"]) ?? 1)
        case .swipe:
            return (.swipe, number(event.metadata?["velocity"]) ?? 1)
        case .call:
            return (.call, 1)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

