import XCTest
@testable import SynheartCore

final class ConsentRuntimeCoordinatorTests: XCTestCase {
    private final class Runtime: NativeConsentManaging {
        var values: [String: Bool] = [:]
        var failingType: String?
        var current: [String: Any]?
        var clearResult = true

        func grantConsent(_ type: String) -> Bool {
            guard failingType != type else { return false }
            values[type] = true
            return true
        }

        func revokeConsent(_ type: String) -> Bool {
            guard failingType != type else { return false }
            values[type] = false
            return true
        }

        func currentConsent() -> [String: Any]? { current }
        func clearStoredConsent() -> Bool { clearResult }
    }

    func testNativeFailureNeverChangesLocalConsentOrEnablesCollection() async throws {
        let module = ConsentModule()
        try await module.initialize()
        let original = module.current()
        let target = original.copyWith(biosignals: true)
        let runtime = Runtime()
        runtime.failingType = ConsentType.biosignals.rawValue

        let error = ConsentRuntimeCoordinator.apply(
            target,
            replacing: original,
            through: runtime
        )
        if error == nil {
            try await module.updateConsent(target)
        }

        XCTAssertNotNil(error)
        XCTAssertFalse(module.current().biosignals)
        XCTAssertFalse(module.current().allows(.biosignals))
    }

    func testFailedBatchRollsBackEarlierNativeMutations() {
        let runtime = Runtime()
        runtime.failingType = ConsentType.behavior.rawValue
        let target = ConsentSnapshot.none().copyWith(
            biosignals: true,
            behavior: true
        )

        XCTAssertNotNil(ConsentRuntimeCoordinator.apply(
            target,
            replacing: .none(),
            through: runtime
        ))
        XCTAssertEqual(runtime.values[ConsentType.biosignals.rawValue], false)
    }

    func testRestoresNativeConsentSnapshot() throws {
        let runtime = Runtime()
        runtime.current = [
            "biosignals": true,
            "phone_context": true,
            "cloud_upload": false,
            "behavior": false,
            "syni": true,
            "vendor_sync": true,
            "timestamp_ms": 1_700_000_000_000 as NSNumber,
            "version": "1.3.0",
        ]

        let restored = try XCTUnwrap(ConsentRuntimeCoordinator.restore(from: runtime))

        XCTAssertTrue(restored.biosignals)
        XCTAssertTrue(restored.phoneContext)
        XCTAssertTrue(restored.syni)
        XCTAssertTrue(restored.vendorSync)
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        XCTAssertEqual(restored.version, "1.3.0")
    }
}
