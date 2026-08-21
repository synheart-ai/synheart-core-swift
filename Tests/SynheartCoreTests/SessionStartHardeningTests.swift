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

    func testCollectionUsesRuntimeEffectiveConsentInsteadOfRequestedConsent() {
        let effective = ConsentEffectiveState(
            biosignals: false,
            phoneContext: false,
            behavior: true,
            cloudUpload: false,
            syni: false,
            vendorSync: false,
            research: false,
            timestampMs: 0,
            version: "1.0.0"
        )

        XCTAssertEqual(SessionStartPolicy.operationalCollectionFeatures(
            consent: effective,
            activated: [.wear, .behavior],
            capabilityAllowed: { _ in true }
        ), [.behavior])
    }

    func testResearchConsentAloneDoesNotPermitCollection() {
        let effective = ConsentEffectiveState(
            biosignals: false,
            phoneContext: false,
            behavior: false,
            cloudUpload: false,
            syni: false,
            vendorSync: false,
            research: true,
            timestampMs: 0,
            version: "1.0.0"
        )

        XCTAssertTrue(SessionStartPolicy.operationalCollectionFeatures(
            consent: effective,
            activated: [.wear, .behavior, .phoneContext],
            capabilityAllowed: { _ in true }
        ).isEmpty)
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

    func testResilientStartKeepsIndependentHealthyModulesRunning() async throws {
        let manager = ModuleManager()
        let first = TestModule(moduleId: "first")
        let failing = TestModule(moduleId: "failing")
        let third = TestModule(moduleId: "third")
        failing.shouldFailStart = true

        try manager.registerModule(first)
        try manager.registerModule(failing)
        try manager.registerModule(third)
        try await manager.initializeAll()

        let report = try await manager.startModulesResiliently(["first", "failing", "third"])

        XCTAssertEqual(report.runningModuleIds, ["first", "third"])
        XCTAssertNotNil(report.failures["failing"])
        XCTAssertEqual(first.status, .running)
        XCTAssertEqual(failing.status, .initialized)
        XCTAssertEqual(third.status, .running)
        await manager.disposeAll()
    }

    func testResilientStartSkipsDependentsOfFailedModule() async throws {
        let manager = ModuleManager()
        let dependency = TestModule(moduleId: "dependency")
        let dependent = TestModule(moduleId: "dependent")
        dependency.shouldFailStart = true

        try manager.registerModule(dependency)
        try manager.registerModule(dependent, dependsOn: ["dependency"])
        try await manager.initializeAll()

        let report = try await manager.startModulesResiliently(["dependent"])

        XCTAssertTrue(report.runningModuleIds.isEmpty)
        XCTAssertNotNil(report.failures["dependency"])
        XCTAssertEqual(report.failures["dependent"], "Dependency failed: dependency")
        XCTAssertEqual(dependent.status, .initialized)
        await manager.disposeAll()
    }
}
