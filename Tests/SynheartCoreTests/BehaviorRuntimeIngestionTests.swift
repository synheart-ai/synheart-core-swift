import XCTest
@testable import SynheartCore

final class BehaviorRuntimeIngestionTests: XCTestCase {
    private final class RuntimeSink: BehaviorRuntimeSinking {
        private(set) var pushes: [(Int64, Int32, Double)] = []

        func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
            pushes.append((tsMs, eventType, value))
        }
    }

    /// A sink on a runtime that exports the rich and context symbols.
    private final class RichRuntimeSink: BehaviorRuntimeSinking {
        private(set) var legacyPushes: [(Int64, Int32, Double)] = []
        private(set) var richKinds: [String] = []
        private(set) var contextVariants: [String] = []

        func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
            legacyPushes.append((tsMs, eventType, value))
        }
        func pushBehaviorEventJson(_ json: String) -> Int32? {
            let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            richKinds.append(obj?["kind"] as? String ?? "?")
            return 0
        }
        func pushContextEventJson(_ json: String) -> Int32? {
            let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            contextVariants.append(obj?.keys.first ?? "?")
            return 0
        }
    }

    private final class Collector: BehaviorCollecting {
        var onEvent: ((BehaviorEvent) -> Void)?
        private(set) var startSessionId: String?
        private(set) var stopped = false

        func start(sessionId: String?) throws {
            startSessionId = sessionId
        }

        func stop() {
            stopped = true
        }

        func emit(_ event: BehaviorEvent) {
            onEvent?(event)
        }
    }

    func testAutomaticBehaviorEventIsForwardedToRuntime() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        try await consent.updateConsent(.none().copyWith(behavior: true))
        let runtime = RuntimeSink()
        let collector = Collector()
        let module = BehaviorModule(
            capabilities: capabilities,
            consent: consent,
            runtimeSink: runtime,
            collector: collector,
            sessionIdProvider: { "sess_test" }
        )

        try await module.initialize()
        try await module.start()
        collector.emit(.scroll(delta: 4.5))

        XCTAssertEqual(collector.startSessionId, "sess_test")
        XCTAssertEqual(runtime.pushes.count, 1)
        XCTAssertEqual(runtime.pushes[0].1, RuntimeBehaviorEvent.scroll.rawValue)
        XCTAssertEqual(runtime.pushes[0].2, 4.5)

        try await module.stop()
        XCTAssertTrue(collector.stopped)
    }

    func testBehaviorEventIsDroppedWithoutConsent() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        let runtime = RuntimeSink()
        let collector = Collector()
        let module = BehaviorModule(
            capabilities: capabilities,
            consent: consent,
            runtimeSink: runtime,
            collector: collector
        )

        try await module.initialize()
        try await module.start()
        collector.emit(.tap(x: 1, y: 2))

        XCTAssertTrue(runtime.pushes.isEmpty)
        XCTAssertTrue(module.rawEvents(.window30s).isEmpty)
        try await module.stop()
    }

    func testRichPathIsPreferredAndContextChannelIsFed() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        try await consent.updateConsent(.none().copyWith(behavior: true))
        let runtime = RichRuntimeSink()
        let collector = Collector()
        let module = BehaviorModule(
            capabilities: capabilities,
            consent: consent,
            runtimeSink: runtime,
            collector: collector
        )
        var observed: [String] = []
        module.onRuntimeBehaviorEvent = { observed.append($0.kind) }

        try await module.initialize()
        try await module.start()
        collector.emit(.scroll(delta: 4.5))
        collector.emit(.tap(x: 1, y: 2))
        collector.emit(.keyDown())

        XCTAssertEqual(runtime.richKinds, ["scroll", "touch"], "rich path first; keystrokes take no rich form")
        XCTAssertEqual(runtime.legacyPushes.count, 1, "only the keystroke falls back to the legacy push")
        XCTAssertEqual(runtime.legacyPushes[0].1, RuntimeBehaviorEvent.input.rawValue)
        XCTAssertEqual(runtime.contextVariants, ["Mouse", "Mouse"], "scroll and tap feed the context channel; keystrokes do not")
        XCTAssertEqual(observed, ["scroll", "touch"])
        try await module.stop()
    }

    func testNotificationOutcomeIsNotPushedAsASecondArrival() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        try await consent.updateConsent(.none().copyWith(behavior: true))
        let runtime = RichRuntimeSink()
        let collector = Collector()
        let module = BehaviorModule(
            capabilities: capabilities,
            consent: consent,
            runtimeSink: runtime,
            collector: collector
        )
        var captured: [BehaviorEventType] = []
        let sub = module.capturedEvents.sink { captured.append($0.type) }
        defer { sub.cancel() }

        try await module.initialize()
        try await module.start()
        collector.emit(.notificationReceived())
        collector.emit(.notificationOpened())

        XCTAssertEqual(runtime.richKinds, ["notification"], "the arrival reaches the runtime once")
        XCTAssertTrue(runtime.legacyPushes.isEmpty, "the follow-up must not fall back to the legacy push either")
        XCTAssertEqual(captured, [.notificationReceived, .notificationOpened], "the host still sees both")
        try await module.stop()
    }

    func testRuntimeEventCodesRemainStable() {
        XCTAssertEqual(RuntimeBehaviorEvent.screenOn.rawValue, 0)
        XCTAssertEqual(RuntimeBehaviorEvent.screenOff.rawValue, 1)
        XCTAssertEqual(RuntimeBehaviorEvent.input.rawValue, 2)
        XCTAssertEqual(RuntimeBehaviorEvent.appSwitch.rawValue, 3)
        XCTAssertEqual(RuntimeBehaviorEvent.notification.rawValue, 4)
        XCTAssertEqual(RuntimeBehaviorEvent.scroll.rawValue, 5)
        XCTAssertEqual(RuntimeBehaviorEvent.swipe.rawValue, 6)
        XCTAssertEqual(RuntimeBehaviorEvent.call.rawValue, 7)
    }
}
