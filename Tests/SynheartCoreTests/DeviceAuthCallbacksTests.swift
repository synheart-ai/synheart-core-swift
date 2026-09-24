import XCTest
@testable import SynheartCore

/// Exercises the host-provided device-auth callbacks directly (no runtime
/// handle needed): the Keychain-backed secure-storage round-trip and that the
/// Secure Enclave crypto symbols resolve + execute.
final class DeviceAuthCallbacksTests: XCTestCase {

    private let service = "synheart.test.deviceauth"
    private let key = "unit-test-key"

    override func tearDown() {
        _ = key.withCString { k in service.withCString { s in DeviceAuthCallbacks.delete(s, k) } }
        super.tearDown()
    }

    func testStorageRoundTrip() throws {
        let value = "consent-token-blob-123"

        let stored = value.withCString { v in
            key.withCString { k in service.withCString { s in
                DeviceAuthCallbacks.store(s, k, v)
            } }
        }
        try XCTSkipIf(stored != 0, "Keychain unavailable in this test host (entitlements)")

        // load returns a malloc'd C string the runtime would free; copy + free here.
        let loaded: String? = key.withCString { k in
            service.withCString { s in
                guard let ptr = DeviceAuthCallbacks.load(s, k) else { return nil }
                defer { free(ptr) }
                return String(cString: ptr)
            }
        }
        XCTAssertEqual(loaded, value)

        let deleted = key.withCString { k in service.withCString { s in DeviceAuthCallbacks.delete(s, k) } }
        XCTAssertEqual(deleted, 0)

        let afterDelete = key.withCString { k in service.withCString { s in DeviceAuthCallbacks.load(s, k) } }
        XCTAssertNil(afterDelete, "value should be gone after delete")
    }

    func testCryptoSymbolsResolveAndExecute() {
        // Proves SynheartAuth's @_cdecl symbols are linked + callable. key_exists
        // for an unknown device id must return 0 (no Secure Enclave key needed).
        let cb = DeviceAuthCallbacks.cryptoCallbacks()
        let exists = "no-such-device-\(UUID().uuidString)".withCString { cb.key_exists($0) }
        XCTAssertEqual(exists, 0)
    }
}

/// The absent / unavailable split behind `secure_load`, exercised without a
/// Keychain: the C callback can only return a pointer or NULL, so the SDK
/// must decide *before* that boundary which statuses are worth retrying.
final class DeviceAuthSecureLoadClassificationTests: XCTestCase {

    func testLockedAndNotReadyStatusesAreTransient() {
        XCTAssertTrue(DeviceAuthCallbacks.keychainStatusIsTransient(errSecInteractionNotAllowed))
        XCTAssertTrue(DeviceAuthCallbacks.keychainStatusIsTransient(errSecNotAvailable))
        XCTAssertTrue(DeviceAuthCallbacks.keychainStatusIsTransient(errSecIO))
    }

    func testPermanentStatusesAreNotRetried() {
        XCTAssertFalse(DeviceAuthCallbacks.keychainStatusIsTransient(errSecParam))
        XCTAssertFalse(DeviceAuthCallbacks.keychainStatusIsTransient(errSecMissingEntitlement))
        XCTAssertFalse(DeviceAuthCallbacks.keychainStatusIsTransient(errSecDecode))
        XCTAssertFalse(DeviceAuthCallbacks.keychainStatusIsTransient(errSecItemNotFound))
    }

    func testMissingItemIsReportedAsAbsentNotUnavailable() throws {
        let outcome = DeviceAuthCallbacks.keychainLoadOnce(
            service: "synheart.test.deviceauth.absent",
            account: "never-stored-\(UUID().uuidString)"
        )
        // A host without Keychain entitlements answers with an error status;
        // only a reachable Keychain can prove the absent branch.
        try XCTSkipIf({ if case .unavailable = outcome { return true }; return false }(),
                      "Keychain unavailable in this test host (entitlements)")
        XCTAssertEqual(outcome, .absent)
    }
}
