import XCTest
@testable import SynheartCore

final class BehaviorRuntimeIngestionTests: XCTestCase {
    private final class RuntimeSink: BehaviorRuntimeSinking {
        private(set) var pushes: [(Int64, Int32, Double)] = []

        func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
            pushes.append((tsMs, eventType, value))
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
