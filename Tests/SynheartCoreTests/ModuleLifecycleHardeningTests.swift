import XCTest
@testable import SynheartCore

final class ModuleLifecycleHardeningTests: XCTestCase {
    func testWearModuleUsesManagedLifecycleWithoutImplicitMockSource() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        let module = WearModule(capabilities: capabilities, consent: consent)

        XCTAssertEqual(module.status, .uninitialized)

        try await module.initialize()
        XCTAssertEqual(module.status, .initialized)

        try await module.start()
        XCTAssertEqual(module.status, .running)
        XCTAssertTrue(module.rawSamples(.window30s).isEmpty)

        try await module.stop()
        XCTAssertEqual(module.status, .stopped)

        try await module.dispose()
        XCTAssertEqual(module.status, .disposed)
        try await consent.dispose()
    }

    func testBehaviorModuleUsesManagedLifecycle() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        let module = BehaviorModule(capabilities: capabilities, consent: consent)

        try await module.initialize()
        XCTAssertEqual(module.status, .initialized)

        try await module.start()
        XCTAssertEqual(module.status, .running)

        try await module.stop()
        XCTAssertEqual(module.status, .stopped)

        try await module.dispose()
        XCTAssertEqual(module.status, .disposed)
        try await consent.dispose()
    }

    func testPhoneModuleUsesManagedInitializationLifecycle() async throws {
        let capabilities = CapabilityModule()
        capabilities.loadDefaults()
        let consent = ConsentModule()
        try await consent.initialize()
        let module = PhoneModule(capabilities: capabilities, consent: consent)

        try await module.initialize()
        XCTAssertEqual(module.status, .initialized)

        try await module.dispose()
        XCTAssertEqual(module.status, .disposed)
        try await consent.dispose()
    }
}
