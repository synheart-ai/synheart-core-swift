import XCTest
@testable import SynheartCore

final class HSIDeliveryDeduplicatorTests: XCTestCase {
    func testDropsRepeatedCanonicalHsiId() {
        let gate = HSIDeliveryDeduplicator()
        let payload = #"{"hsi_version":"1.3","meta":{"ids":{"hsi_id":"same"}}}"#

        XCTAssertTrue(gate.shouldDeliver(json: payload))
        XCTAssertFalse(gate.shouldDeliver(json: payload))
    }

    func testLegacyPayloadsWithoutIdentityAreAlwaysDelivered() {
        let gate = HSIDeliveryDeduplicator()
        let payload = #"{"timestamp_ms":1,"hsi":{}}"#

        XCTAssertTrue(gate.shouldDeliver(json: payload))
        XCTAssertTrue(gate.shouldDeliver(json: payload))
    }

    func testBoundedHistoryEventuallyAllowsEvictedIdentity() {
        let gate = HSIDeliveryDeduplicator(capacity: 2)

        XCTAssertTrue(gate.shouldDeliver(json: payload(id: "one")))
        XCTAssertTrue(gate.shouldDeliver(json: payload(id: "two")))
        XCTAssertTrue(gate.shouldDeliver(json: payload(id: "three")))
        XCTAssertTrue(gate.shouldDeliver(json: payload(id: "one")))
    }

    func testResetStartsFreshIdentityWindow() {
        let gate = HSIDeliveryDeduplicator()
        let payload = payload(id: "one")

        XCTAssertTrue(gate.shouldDeliver(json: payload))
        gate.reset()
        XCTAssertTrue(gate.shouldDeliver(json: payload))
    }

    private func payload(id: String) -> String {
        #"{"meta":{"ids":{"hsi_id":"\#(id)"}}}"#
    }
}
