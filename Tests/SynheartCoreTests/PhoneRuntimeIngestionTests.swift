import Combine
import XCTest
@testable import SynheartCore

final class PhoneRuntimeIngestionTests: XCTestCase {
    private final class RuntimeSink: PhoneRuntimeSinking {
        private(set) var pushes: [(Int64, Double, Double, Double)] = []

        func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double) {
            pushes.append((tsMs, x, y, z))
        }
    }

    private final class MotionCollector: MotionCollecting {
        let subject = PassthroughSubject<MotionData, Error>()
        var motionStream: AnyPublisher<MotionData, Error> { subject.eraseToAnyPublisher() }
        var currentMotionLevelValue: Double { 0 }
        func start() async throws {}
        func stop() async throws {}
        func dispose() async throws {}
    }

    private final class NoOpScreenTracker: ScreenStateTracking {
        private let subject = PassthroughSubject<ScreenState, Error>()
        var screenStream: AnyPublisher<ScreenState, Error> { subject.eraseToAnyPublisher() }
        var isScreenOn: Bool { false }
        func start() async throws {}
        func stop() async throws {}
        func dispose() async throws {}
    }

    func testConsentedMotionIsCachedPublishedAndForwardedToRuntime() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        try await consent.updateConsent(.none().copyWith(phoneContext: true))
        let collector = MotionCollector()
        let runtime = RuntimeSink()
        let module = PhoneModule(
            capabilities: capabilities,
            consent: consent,
            motionCollector: collector,
            screenTracker: NoOpScreenTracker(),
            runtimeSink: runtime
        )
        var published = 0
        let subscription = module.motionSamples.sink { _ in published += 1 }

        try await module.initialize()
        try await module.start()
        let timestamp = Date(timeIntervalSince1970: 1_776_000_000)
        collector.subject.send(MotionData(x: 0.1, y: 0.2, z: 0.3, energy: 0.4, timestamp: timestamp))

        XCTAssertEqual(runtime.pushes.count, 1)
        XCTAssertEqual(runtime.pushes[0].0, 1_776_000_000_000)
        XCTAssertEqual(runtime.pushes[0].1, 0.1)
        XCTAssertEqual(runtime.pushes[0].2, 0.2)
        XCTAssertEqual(runtime.pushes[0].3, 0.3)
        XCTAssertEqual(module.rawDataPoints(.window30s).count, 1)
        XCTAssertEqual(published, 1)

        subscription.cancel()
        try await module.stop()
    }

    func testMotionStopsImmediatelyAfterConsentRevocation() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        try await consent.updateConsent(.none().copyWith(phoneContext: true))
        let collector = MotionCollector()
        let runtime = RuntimeSink()
        let module = PhoneModule(
            capabilities: capabilities,
            consent: consent,
            motionCollector: collector,
            screenTracker: NoOpScreenTracker(),
            runtimeSink: runtime
        )

        try await module.initialize()
        try await module.start()
        try await consent.updateConsent(.none())
        collector.subject.send(MotionData(x: 1, y: 1, z: 1, energy: 1, timestamp: Date()))

        XCTAssertTrue(runtime.pushes.isEmpty)
        XCTAssertTrue(module.rawDataPoints(.window30s).isEmpty)
        try await module.stop()
    }
}
