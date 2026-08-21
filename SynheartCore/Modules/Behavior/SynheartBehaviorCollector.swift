#if canImport(SynheartBehavior)
import Foundation
import SynheartBehavior

final class SynheartBehaviorCollector: BehaviorCollecting {
    var onEvent: ((BehaviorEvent) -> Void)?

    private var sdk: SynheartBehavior?

    func start(sessionId: String?) throws {
        guard sdk == nil else { return }
        let sdk = SynheartBehavior(config: BehaviorConfig(
            enableInputSignals: true,
            enableAttentionSignals: true,
            enableMotionLite: false,
            consentBehavior: true
        ))
        sdk.setEventHandler { [weak self] event in
            guard let converted = Self.convert(
                type: event.eventType.rawValue,
                timestamp: event.timestamp,
                metrics: event.metrics
            ) else { return }
            self?.onEvent?(converted)
        }
        try sdk.initialize()
        _ = try sdk.startSession(sessionId: sessionId)
        self.sdk = sdk
    }

    func stop() {
        guard let sdk else { return }
        if let sessionId = sdk.getCurrentSessionId() {
            _ = try? sdk.endSession(sessionId: sessionId)
        }
        sdk.dispose()
        self.sdk = nil
    }

    private static func convert(
        type: String,
        timestamp rawTimestamp: String,
        metrics: [String: Any]
    ) -> BehaviorEvent? {
        let timestamp = ISO8601DateFormatter().date(from: rawTimestamp) ?? Date()
        switch type {
        case "tap":
            return BehaviorEvent(
                type: .tap,
                timestamp: timestamp,
                metadata: metrics
            )
        case "scroll":
            return BehaviorEvent(
                type: .scroll,
                timestamp: timestamp,
                metadata: ["delta": numeric(metrics["velocity"]) ?? 1]
            )
        case "swipe":
            return BehaviorEvent(
                type: .swipe,
                timestamp: timestamp,
                metadata: metrics
            )
        case "typing":
            return BehaviorEvent(type: .keyDown, timestamp: timestamp, metadata: metrics)
        case "notification":
            let action = metrics["action"] as? String
            return BehaviorEvent(
                type: action == "opened" ? .notificationOpened : .notificationReceived,
                timestamp: timestamp,
                metadata: metrics
            )
        case "call":
            return BehaviorEvent(type: .call, timestamp: timestamp, metadata: metrics)
        case "app_switch":
            return BehaviorEvent(type: .appSwitch, timestamp: timestamp, metadata: metrics)
        default:
            return nil
        }
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
#endif
