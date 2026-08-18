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

    func testCollectionConsentRequiresAtLeastOneLocalSignalClass() {
        XCTAssertFalse(SessionStartPolicy.hasCollectionConsent(.none()))
        XCTAssertTrue(SessionStartPolicy.hasCollectionConsent(ConsentSnapshot(
            biosignals: true,
            behavior: false,
            phoneContext: false,
            cloudUpload: false,
            syni: false
        )))
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
