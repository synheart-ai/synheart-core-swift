import XCTest
@testable import SynheartCore

final class InitializationGateTests: XCTestCase {
    private actor AttemptCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    private enum ExpectedFailure: Error {
        case runtimeUnavailable
    }

    func testConcurrentCallersShareAttemptAndFailureCanBeRetried() async {
        let gate = InitializationGate()
        let attempts = AttemptCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        try await gate.run {
                            await attempts.increment()
                            try await Task.sleep(nanoseconds: 100_000_000)
                            throw ExpectedFailure.runtimeUnavailable
                        }
                        XCTFail("Expected initialization to fail")
                    } catch ExpectedFailure.runtimeUnavailable {
                        // Expected: every caller receives the shared failure.
                    } catch {
                        XCTFail("Unexpected error: \(error)")
                    }
                }
            }
        }

        let attemptsAfterSharedFailure = await attempts.value
        XCTAssertEqual(attemptsAfterSharedFailure, 1)

        do {
            try await gate.run {
                await attempts.increment()
                throw ExpectedFailure.runtimeUnavailable
            }
            XCTFail("Expected retry to fail")
        } catch ExpectedFailure.runtimeUnavailable {
            // The important assertion is that a fresh attempt ran.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let attemptsAfterRetry = await attempts.value
        XCTAssertEqual(attemptsAfterRetry, 2)
    }
}
