import XCTest
@testable import SynheartCore

final class SessionStartHardeningTests: XCTestCase {
    private final class TestModule: BaseSynheartModule {
        var shouldFailStart = false
        private(set) var stopCount = 0

        override func onStart() async throws {
            if shouldFailStart {
                throw ModuleException(moduleId, "expected failure")
            }
        }

        override func onStop() async throws {
            stopCount += 1
        }
    }

    func testCollectionRequiresMatchingActivationConsentAndCapability() {
        let biosignalConsent = ConsentSnapshot(
            biosignals: true,
            behavior: false,
            phoneContext: false,
            cloudUpload: false,
            syni: false
        )

        XCTAssertTrue(SessionStartPolicy.operationalCollectionFeatures(
            consent: biosignalConsent,
            activated: [],
            capabilityAllowed: { _ in true }
        ).isEmpty)
        XCTAssertTrue(SessionStartPolicy.operationalCollectionFeatures(
            consent: biosignalConsent,
            activated: [.behavior],
            capabilityAllowed: { _ in true }
        ).isEmpty)
        XCTAssertTrue(SessionStartPolicy.operationalCollectionFeatures(
            consent: biosignalConsent,
            activated: [.wear],
            capabilityAllowed: { _ in false }
        ).isEmpty)
        XCTAssertEqual(SessionStartPolicy.operationalCollectionFeatures(
            consent: biosignalConsent,
            activated: [.wear],
            capabilityAllowed: { _ in true }
        ), [.wear])
    }

    func testBiosignalConsentDoesNotStartOrCachePhoneData() async throws {
        let manager = ModuleManager()
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        let wear = TestModule(moduleId: "wear")
        let phone = PhoneModule(capabilities: capabilities, consent: consent)

        try manager.registerModule(capabilities)
        try manager.registerModule(consent)
        try manager.registerModule(wear, dependsOn: ["capabilities", "consent"])
        try manager.registerModule(phone, dependsOn: ["capabilities", "consent"])
        try await manager.initializeAll()
        try await consent.updateConsent(ConsentSnapshot(
            biosignals: true,
            behavior: false,
            phoneContext: false,
            cloudUpload: false,
            syni: false
        ))

        let allowed = SessionStartPolicy.operationalCollectionFeatures(
            consent: consent.current(),
            activated: [.wear],
            capabilityAllowed: { _ in true }
        )
        try await manager.startModules(Set(allowed.map(\.rawValue)))

        XCTAssertEqual(wear.status, .running)
        XCTAssertEqual(phone.status, .initialized)

        phone.cacheMotionIfConsented(MotionData(
            x: 1,
            y: 1,
            z: 1,
            energy: 1,
            timestamp: Date()
        ))
        try await consent.updateConsent(consent.current().copyWith(phoneContext: true))
        XCTAssertTrue(phone.rawDataPoints(.window30s).isEmpty)

        await manager.disposeAll()
    }

    func testModuleManagerRollsBackPartialStartAndCanRetry() async throws {
        let manager = ModuleManager()
        let first = TestModule(moduleId: "first")
        let second = TestModule(moduleId: "second")
        second.shouldFailStart = true

        try manager.registerModule(first)
        try manager.registerModule(second, dependsOn: ["first"])
        try await manager.initializeAll()

        do {
            try await manager.startAll()
            XCTFail("Expected second module to fail")
        } catch {
            XCTAssertEqual(first.status, .stopped)
            XCTAssertEqual(second.status, .initialized)
        }

        second.shouldFailStart = false
        try await manager.startAll()
        XCTAssertEqual(first.status, .running)
        XCTAssertEqual(second.status, .running)
    }
}
