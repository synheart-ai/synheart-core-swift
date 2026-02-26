import XCTest
import Combine
@testable import SynheartCore

final class HSVIntegrationTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func mockHSV(
        heartRate: Float? = 75.0,
        hrvRmssd: Float? = 50.0,
        behavior: BehaviorState? = nil
    ) -> HumanStateVector {
        HumanStateVector(
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            meta: MetaState(
                device: DeviceInfo(platform: "test", osVersion: "1.0", deviceModel: "test", deviceId: "test-device"),
                sessionId: "test-session"
            ),
            heartRate: heartRate,
            hrvRmssd: hrvRmssd,
            behavior: behavior
        )
    }

    // MARK: - HSV Model Tests

    func testHSVInitialization() {
        let hsv = mockHSV()
        XCTAssertNotNil(hsv.meta)
        XCTAssertEqual(hsv.heartRate, 75.0)
        XCTAssertEqual(hsv.hrvRmssd, 50.0)
    }

    func testHSVWithBehavior() {
        let behavior = BehaviorState(typingSpeed: 0.5, scrollVelocity: 0.3, appSwitchRate: 0.2)
        let hsv = mockHSV(behavior: behavior)
        XCTAssertNotNil(hsv.behavior)
        XCTAssertEqual(hsv.behavior?.typingSpeed, 0.5)
        XCTAssertEqual(hsv.behavior?.scrollVelocity, 0.3)
    }
}
