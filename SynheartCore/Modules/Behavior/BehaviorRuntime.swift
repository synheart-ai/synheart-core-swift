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
    /// Legacy int-coded push; carries no payload.
    func pushBehavior(tsMs: Int64, eventType: Int32, value: Double)
    /// Rich, payload-carrying push. `nil` when the runtime lacks the symbol,
    /// which is the module's signal to fall back to `pushBehavior`.
    func pushBehaviorEventJson(_ json: String) -> Int32?
    /// Context-evidence channel. `nil` when the runtime lacks the symbol.
    func pushContextEventJson(_ json: String) -> Int32?
}

extension BehaviorRuntimeSinking {
    func pushBehaviorEventJson(_ json: String) -> Int32? { nil }
    func pushContextEventJson(_ json: String) -> Int32? { nil }
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

    /// Whether `event` is a later outcome of a notification the host has
    /// already reported, not a new arrival.
    ///
    /// The host reports a notification on arrival (`notificationReceived`) and
    /// again with its outcome (`notificationOpened`). The engine counts every
    /// notification event as an arrival and reads the action as a label on it,
    /// so each follow-up was a second arrival: an opened notification counted
    /// twice, inflating the notification rate, Interruption Pressure and the
    /// lab summary. The module skips the runtime push for these; they stay on
    /// the host-facing event stream.
    static func isNotificationFollowUp(_ event: BehaviorEvent) -> Bool {
        event.type == .notificationOpened
    }

    /// Translate a host-recorded event into the engine's rich form.
    ///
    /// Only what the host actually recorded is forwarded: a tap carries no
    /// duration and a scroll no velocity here, and inventing either would be a
    /// measured value the engine scores on. Returns `nil` for an event the
    /// engine has no variant for; the caller then takes the legacy path.
    /// Keystrokes are deliberately `nil`: a single key is not a typing window.
    static func translateBehaviorEvent(_ event: BehaviorEvent) -> BehaviorEventInput? {
        let ts = Int64(event.timestamp.timeIntervalSince1970 * 1_000)
        switch event.type {
        case .tap:
            return .touch(ts)
        case .scroll:
            return .scroll(ts)
        case .swipe:
            let direction = (event.metadata?["direction"] as? String).flatMap(ScrollDirection.init(rawValue:))
            return .swipe(ts, direction: direction, velocity: number(event.metadata?["velocity"]))
        case .appSwitch:
            return .appSwitch(ts)
        case .notificationReceived:
            return .notification(ts)
        case .notificationOpened:
            return .notification(ts, action: .opened)
        case .call:
            return .call(ts)
        case .keyDown, .keyUp:
            return nil
        }
    }

    /// Translate a host-recorded event into a **context** event, the second
    /// channel beside the behaviour one. A tap here is a real pointer tap (the
    /// gesture path, not a keystroke), so forwarding it as a click does not
    /// inflate the click count with typing. Keystrokes are still dropped:
    /// keyboard evidence enters exclusively from the host's text layer via
    /// `ContextEventInput.textChange`, where an insertion can be told from a
    /// deletion. Interruptions and attention boundaries are not input evidence.
    static func translateContextEvent(_ event: BehaviorEvent) -> ContextEventInput? {
        let ts = Int64(event.timestamp.timeIntervalSince1970 * 1_000)
        switch event.type {
        case .tap:
            return .mouse(ts, .leftClick)
        case .scroll:
            return .mouse(ts, .scroll)
        case .swipe:
            return .mouse(ts, .move)
        case .keyDown, .keyUp, .appSwitch, .notificationReceived, .notificationOpened, .call:
            return nil
        }
    }
}
