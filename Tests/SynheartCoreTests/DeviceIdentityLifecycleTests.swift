import Foundation
import XCTest
@testable import SynheartCore

final class DeviceIdentityLifecycleTests: XCTestCase {
    func testCanonicalSubjectMatchingAndOlderRuntimeCompatibility() {
        XCTAssertTrue(DeviceAuthStatus(status: "registered").matchesSubject("sub_canonical"))
        let restored = DeviceAuthStatus(runtimeMap: [
            "status": "registered", "subject_id": "sub_canonical", "device_id": "dev_1",
        ])
        XCTAssertTrue(restored.matchesSubject("sub_canonical"))
        XCTAssertFalse(restored.matchesSubject("raw_client_id"))
        XCTAssertFalse(restored.matchesSubject("sub_other_account"))
    }

    func testAccountMismatchRemainsTypedAndNonRetryable() {
        let raw = #"{"error":{"code":"DEVICE_ACCOUNT_MISMATCH","reason":"policy","message":"Account mismatch","retryable":false,"detail":{"subject_id":"sub_other"}}}"#
        XCTAssertThrowsError(try DeviceIdentityResponse.decode(raw, operation: "Registration")) { error in
            guard let failure = error as? NativeOperationFailure else { return XCTFail("Lost typed failure") }
            XCTAssertTrue(failure.isAccountMismatch)
            XCTAssertFalse(failure.retryable)
            XCTAssertEqual(failure.reason, .policy)
            XCTAssertNotNil(failure.detail)
        }
    }

    func testMalformedAndEmptyNativeResponsesCannotSucceed() {
        for raw in [nil, "", "null", "[]", "not json"] as [String?] {
            XCTAssertThrowsError(try DeviceIdentityResponse.decode(raw, operation: "Logout"))
        }
        XCTAssertThrowsError(try DeviceIdentityResponse.decode(#"{"ok":false}"#, operation: "Logout"))
    }

    func testSuccessfulLogoutAndReattestationPayloads() throws {
        XCTAssertEqual(try DeviceIdentityResponse.decode(#"{"ok":true}"#, operation: "Logout")["ok"] as? Bool, true)
        XCTAssertEqual(try DeviceIdentityResponse.decode(#"{"device_id":"dev_same"}"#, operation: "Re-attestation")["device_id"] as? String, "dev_same")
    }

    func testCore024IdentitySymbolsRemainOptional() {
        let additions: Set<String> = ["synheart_core_sdk_reattest_device", "synheart_core_sdk_logout"]
        XCTAssertTrue(additions.isSubset(of: RuntimeSymbolManifest.optional))
        XCTAssertTrue(RuntimeSymbolManifest.audit(resolvedSymbols: RuntimeSymbolManifest.all.subtracting(additions)).isCompatible)
    }

    func testSameHandleOperationsAreSerializedOffMainThread() async {
        let queue = RuntimeOperationQueue()
        let state = IdentityWorkState()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await queue.run {
                        XCTAssertFalse(Thread.isMainThread)
                        state.enter()
                        Thread.sleep(forTimeInterval: 0.002)
                        state.leave()
                    }
                }
            }
        }
        XCTAssertEqual(state.maximum, 1)
    }

    func testDifferentHandlesDoNotBlockEachOther() async {
        let first = RuntimeOperationQueue()
        let second = RuntimeOperationQueue()
        let started = expectation(description: "First handle started")
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            await first.run {
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let independent = await second.run { true }
        XCTAssertTrue(independent)
        release.signal()
        await task.value
    }

    func testQueuedClosureRetainsOwnerUntilWorkFinishes() async {
        let queue = RuntimeOperationQueue()
        let released = expectation(description: "Owner released after operation")
        let started = expectation(description: "Operation started")
        let finish = DispatchSemaphore(value: 0)
        var owner: IdentityOwner? = IdentityOwner { released.fulfill() }
        let weakOwner = WeakIdentityOwner(owner)
        var task: Task<Void, Never>? = Task { [captured = owner!] in
            await queue.run { [captured] in
                started.fulfill()
                _ = finish.wait(timeout: .now() + 3)
                captured.touch()
            }
        }
        owner = nil
        await fulfillment(of: [started], timeout: 2)
        XCTAssertNotNil(weakOwner.value)
        finish.signal()
        await task?.value
        task = nil
        await fulfillment(of: [released], timeout: 2)
        XCTAssertNil(weakOwner.value)
    }
}

private final class IdentityWorkState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var maximum = 0
    func enter() {
        lock.lock(); defer { lock.unlock() }
        active += 1
        maximum = max(maximum, active)
    }
    func leave() { lock.lock(); active -= 1; lock.unlock() }
}

private final class IdentityOwner: @unchecked Sendable {
    let released: () -> Void
    init(_ released: @escaping () -> Void) { self.released = released }
    func touch() {}
    deinit { released() }
}

private final class WeakIdentityOwner {
    weak var value: IdentityOwner?
    init(_ value: IdentityOwner?) { self.value = value }
}
