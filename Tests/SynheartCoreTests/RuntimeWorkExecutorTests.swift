import Foundation
import XCTest
@testable import SynheartCore

final class RuntimeWorkExecutorTests: XCTestCase {
    func testWorkRunsOffMainThread() async {
        let ranOnMainThread = await RuntimeWorkExecutor.run {
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testWorkIsSerialized() async {
        let state = LockedExecutionState()

        async let first: Void = RuntimeWorkExecutor.run {
            state.enter()
            Thread.sleep(forTimeInterval: 0.03)
            state.leave()
        }
        async let second: Void = RuntimeWorkExecutor.run {
            state.enter()
            Thread.sleep(forTimeInterval: 0.03)
            state.leave()
        }

        _ = await (first, second)
        XCTAssertEqual(state.maximumConcurrentCount, 1)
    }
}

private final class LockedExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var maximumCount = 0

    var maximumConcurrentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumCount
    }

    func enter() {
        lock.lock()
        activeCount += 1
        maximumCount = max(maximumCount, activeCount)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        activeCount -= 1
        lock.unlock()
    }
}
