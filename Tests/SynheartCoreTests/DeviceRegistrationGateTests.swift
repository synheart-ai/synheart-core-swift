import XCTest
@testable import SynheartCore

final class DeviceRegistrationGateTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    func testConcurrentCallersShareOneAttempt() async {
        let gate = DeviceRegistrationGate()
        let counter = Counter()

        await withTaskGroup(of: DeviceRegistrationResult.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await gate.run {
                        await counter.increment()
                        try? await Task.sleep(nanoseconds: 75_000_000)
                        return DeviceRegistrationResult(
                            success: true,
                            status: DeviceAuthStatus(status: "registered")
                        )
                    }
                }
            }

            for await result in group {
                XCTAssertTrue(result.success)
            }
        }

        let attemptCount = await counter.value
        XCTAssertEqual(attemptCount, 1)
    }
}
