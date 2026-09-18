import Foundation

/// Direction of a scroll or swipe, as the runtime spells it on the wire.
public enum ScrollDirection: String, CaseIterable, Codable, Sendable {
    case up
    case down
    case left
    case right
}

/// What the person did with an interruption (a notification or a call).
public enum InterruptionAction: String, CaseIterable, Codable, Sendable {
    case ignored
    case opened
    case answered
    case dismissed
}

/// Summary of one typing window, carried by ``BehaviorEventInput/typing(windowStartMs:session:)``.
///
/// Every field is optional and only non-nil fields are serialised, so a host
/// that measures a subset sends exactly that subset. The runtime treats an
/// absent field as *unobserved*, which is different from a measured zero.
public struct TypingSessionData: Equatable, Sendable {
    public var durationSec: Double?
    public var typingSpeedCpm: Double?
    public var typingTapCount: Int?
    public var pauseCount: Int?
    public var meanInterTapIntervalMs: Double?
    public var typingCadenceStability: Double?
    public var typingCadenceVariability: Double?
    public var cadenceStability: Double?
    public var typingGapCount: Int?
    public var typingGapRatio: Double?
    public var typingBurstiness: Double?
    public var typingActivityRatio: Double?
    public var typingInteractionIntensity: Double?
    public var deepTyping: Bool?
    public var numberOfBackspace: Int?
    public var numberOfDelete: Int?
    public var numberOfCut: Int?
    public var numberOfPaste: Int?
    public var numberOfCopy: Int?
    public var keyboardScrollRate: Double?
    public var shortcutCount: Int?
    public var shortcutRate: Double?
    public var typingEfficiency: Double?
    public var holdTimeMean: Double?
    public var latencyVariability: Double?

    public init(
        durationSec: Double? = nil,
        typingSpeedCpm: Double? = nil,
        typingTapCount: Int? = nil,
        pauseCount: Int? = nil,
        meanInterTapIntervalMs: Double? = nil,
        typingCadenceStability: Double? = nil,
        typingCadenceVariability: Double? = nil,
        cadenceStability: Double? = nil,
        typingGapCount: Int? = nil,
        typingGapRatio: Double? = nil,
        typingBurstiness: Double? = nil,
        typingActivityRatio: Double? = nil,
        typingInteractionIntensity: Double? = nil,
        deepTyping: Bool? = nil,
        numberOfBackspace: Int? = nil,
        numberOfDelete: Int? = nil,
        numberOfCut: Int? = nil,
        numberOfPaste: Int? = nil,
        numberOfCopy: Int? = nil,
        keyboardScrollRate: Double? = nil,
        shortcutCount: Int? = nil,
        shortcutRate: Double? = nil,
        typingEfficiency: Double? = nil,
        holdTimeMean: Double? = nil,
        latencyVariability: Double? = nil
    ) {
        self.durationSec = durationSec
        self.typingSpeedCpm = typingSpeedCpm
        self.typingTapCount = typingTapCount
        self.pauseCount = pauseCount
        self.meanInterTapIntervalMs = meanInterTapIntervalMs
        self.typingCadenceStability = typingCadenceStability
        self.typingCadenceVariability = typingCadenceVariability
        self.cadenceStability = cadenceStability
        self.typingGapCount = typingGapCount
        self.typingGapRatio = typingGapRatio
        self.typingBurstiness = typingBurstiness
        self.typingActivityRatio = typingActivityRatio
        self.typingInteractionIntensity = typingInteractionIntensity
        self.deepTyping = deepTyping
        self.numberOfBackspace = numberOfBackspace
        self.numberOfDelete = numberOfDelete
        self.numberOfCut = numberOfCut
        self.numberOfPaste = numberOfPaste
        self.numberOfCopy = numberOfCopy
        self.keyboardScrollRate = keyboardScrollRate
        self.shortcutCount = shortcutCount
        self.shortcutRate = shortcutRate
        self.typingEfficiency = typingEfficiency
        self.holdTimeMean = holdTimeMean
        self.latencyVariability = latencyVariability
    }

    /// Wire form: snake_case keys, absent fields omitted.
    public func toJSON() -> [String: Any] {
        var out: [String: Any] = [:]
        if let v = durationSec { out["duration_sec"] = v }
        if let v = typingSpeedCpm { out["typing_speed_cpm"] = v }
        if let v = typingTapCount { out["typing_tap_count"] = v }
        if let v = pauseCount { out["pause_count"] = v }
        if let v = meanInterTapIntervalMs { out["mean_inter_tap_interval_ms"] = v }
        if let v = typingCadenceStability { out["typing_cadence_stability"] = v }
        if let v = typingCadenceVariability { out["typing_cadence_variability"] = v }
        if let v = cadenceStability { out["cadence_stability"] = v }
        if let v = typingGapCount { out["typing_gap_count"] = v }
        if let v = typingGapRatio { out["typing_gap_ratio"] = v }
        if let v = typingBurstiness { out["typing_burstiness"] = v }
        if let v = typingActivityRatio { out["typing_activity_ratio"] = v }
        if let v = typingInteractionIntensity { out["typing_interaction_intensity"] = v }
        if let v = deepTyping { out["deep_typing"] = v }
        if let v = numberOfBackspace { out["number_of_backspace"] = v }
        if let v = numberOfDelete { out["number_of_delete"] = v }
        if let v = numberOfCut { out["number_of_cut"] = v }
        if let v = numberOfPaste { out["number_of_paste"] = v }
        if let v = numberOfCopy { out["number_of_copy"] = v }
        if let v = keyboardScrollRate { out["keyboard_scroll_rate"] = v }
        if let v = shortcutCount { out["shortcut_count"] = v }
        if let v = shortcutRate { out["shortcut_rate"] = v }
        if let v = typingEfficiency { out["typing_efficiency"] = v }
        if let v = holdTimeMean { out["hold_time_mean"] = v }
        if let v = latencyVariability { out["latency_variability"] = v }
        return out
    }
}

/// One typed behavior event for `synheart_core_push_behavior_event`.
///
/// This is the rich, payload-carrying path. The legacy
/// `synheart_core_push_behavior(ts, code, value)` carries no payload at all, so
/// a notification pushed that way has no `action` and a typing event has an
/// all-empty session summary. Prefer this type for anything with structure.
///
/// Build events through the static factories; the wire envelope is
/// `{ "ts_ms", "kind", "value", "data"? }`.
public struct BehaviorEventInput: Equatable, Sendable {
    /// Epoch milliseconds of the event (for ``typing(windowStartMs:session:)``,
    /// the start of the typing window).
    public let tsMs: Int64
    /// The runtime's event kind tag, e.g. `touch`, `scroll`, `app_foreground`.
    public let kind: String
    /// Scalar payload for kinds that carry one (`system_failure`); `0` otherwise.
    public let value: Double
    /// Kind-specific payload. Empty for kinds that have none.
    public let data: [String: JSONValue]

    init(tsMs: Int64, kind: String, value: Double = 0, data: [String: JSONValue] = [:]) {
        self.tsMs = tsMs
        self.kind = kind
        self.value = value
        self.data = data
    }

    // MARK: Factories

    public static func touch(_ tsMs: Int64, durationMs: Int? = nil, longPress: Bool? = nil) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let durationMs { d["duration_ms"] = .int(durationMs) }
        if let longPress { d["long_press"] = .bool(longPress) }
        return .init(tsMs: tsMs, kind: "touch", data: d)
    }

    public static func scroll(
        _ tsMs: Int64,
        velocity: Double? = nil,
        direction: ScrollDirection? = nil,
        directionReversal: Bool? = nil
    ) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let velocity { d["velocity"] = .double(velocity) }
        if let direction { d["direction"] = .string(direction.rawValue) }
        if let directionReversal { d["direction_reversal"] = .bool(directionReversal) }
        return .init(tsMs: tsMs, kind: "scroll", data: d)
    }

    public static func swipe(_ tsMs: Int64, direction: ScrollDirection? = nil, velocity: Double? = nil) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let direction { d["direction"] = .string(direction.rawValue) }
        if let velocity { d["velocity"] = .double(velocity) }
        return .init(tsMs: tsMs, kind: "swipe", data: d)
    }

    public static func appSwitch(_ tsMs: Int64, fromApp: String? = nil, toApp: String? = nil) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let fromApp { d["from_app"] = .string(fromApp) }
        if let toApp { d["to_app"] = .string(toApp) }
        return .init(tsMs: tsMs, kind: "app_switch", data: d)
    }

    /// The application currently in the foreground. Send an app *identifier*
    /// (bundle identifier); the runtime maps it to a category on-device and
    /// never stores the identifier in the human-state output.
    public static func appForeground(_ tsMs: Int64, app: String) -> BehaviorEventInput {
        .init(tsMs: tsMs, kind: "app_foreground", data: ["app": .string(app)])
    }

    public static func notification(_ tsMs: Int64, action: InterruptionAction? = nil, sourceApp: String? = nil) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let action { d["action"] = .string(action.rawValue) }
        if let sourceApp { d["source_app"] = .string(sourceApp) }
        return .init(tsMs: tsMs, kind: "notification", data: d)
    }

    public static func call(_ tsMs: Int64, action: InterruptionAction? = nil) -> BehaviorEventInput {
        var d: [String: JSONValue] = [:]
        if let action { d["action"] = .string(action.rawValue) }
        return .init(tsMs: tsMs, kind: "call", data: d)
    }

    /// One completed typing window. `windowStartMs` is the window's start, not
    /// the time of the push.
    public static func typing(windowStartMs: Int64, session: TypingSessionData) -> BehaviorEventInput {
        .init(tsMs: windowStartMs, kind: "typing", data: JSONValue.dictionary(from: session.toJSON()))
    }

    public static func screenOn(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "screen_on") }
    public static func screenOff(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "screen_off") }
    public static func taskSuccess(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "task_success") }
    public static func taskFailure(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "task_failure") }
    public static func taskReturn(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "task_return") }
    public static func taskAbandonment(_ tsMs: Int64) -> BehaviorEventInput { .init(tsMs: tsMs, kind: "task_abandonment") }

    /// A system failure the person experienced (hang, crash, error dialog),
    /// with how long it lasted. The duration rides in both `value` and `data`.
    public static func systemFailure(_ tsMs: Int64, durationSecs: Double) -> BehaviorEventInput {
        .init(tsMs: tsMs, kind: "system_failure", value: durationSecs, data: ["duration_secs": .double(durationSecs)])
    }

    // MARK: Wire form

    /// The JSON object the runtime parses.
    public func toJSON() -> [String: Any] {
        var out: [String: Any] = [
            "ts_ms": tsMs,
            "kind": kind,
            "value": value,
        ]
        if !data.isEmpty { out["data"] = JSONValue.foundation(from: data) }
        return out
    }

    /// Serialised wire form, or nil if the payload cannot be encoded.
    public func toJSONString() -> String? {
        JSONValue.encode(toJSON())
    }
}

/// A small JSON value type so event payloads stay `Equatable` and `Sendable`
/// while still bridging to `JSONSerialization`.
public enum JSONValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    indirect case array([JSONValue])
    indirect case object([String: JSONValue])

    /// Foundation representation accepted by `JSONSerialization`.
    public var foundationValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map { $0.foundationValue }
        case .object(let o): return JSONValue.foundation(from: o)
        }
    }

    static func foundation(from dict: [String: JSONValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict { out[k] = v.foundationValue }
        return out
    }

    /// Best-effort conversion of a Foundation JSON object. Unknown leaf types
    /// are dropped rather than crashing.
    static func dictionary(from dict: [String: Any]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (k, v) in dict {
            if let j = JSONValue(any: v) { out[k] = j }
        }
        return out
    }

    init?(any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .int(i)
        case let d as Double: self = .double(d)
        case let n as NSNumber:
            // NSNumber is reached for boxed values; Bool is handled above on
            // platforms where it bridges distinctly.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 9.0e15 { self = .int(n.intValue) }
            else { self = .double(n.doubleValue) }
        case is NSNull: self = .null
        case let a as [Any]: self = .array(a.compactMap { JSONValue(any: $0) })
        case let o as [String: Any]: self = .object(JSONValue.dictionary(from: o))
        default: return nil
        }
    }

    /// Encode a Foundation JSON object with stable key order.
    static func encode(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
