import XCTest
@testable import SynheartCore

final class HSIStateTests: XCTestCase {

    func testParsesNestedHSIJson() {
        let json = """
        {"subject_id":"usr_123","timestamp_ms":1700000000000,"hsi":{"focus":{"value":0.8,"confidence":0.9},"arousal":{"value":0.5,"confidence":0.7},"capacity":{"value":0.6,"confidence":0.8},"sleep":{"value":0.3,"confidence":0.95}}}
        """
        let state = HSIState.fromJson(json)
        XCTAssertEqual(state.subjectId, "usr_123")
        XCTAssertEqual(state.timestampMs, 1700000000000)
        XCTAssertEqual(state.hsi.focus?.value, 0.8)
        XCTAssertEqual(state.hsi.focus?.confidence, 0.9)
        XCTAssertEqual(state.hsi.arousal?.value, 0.5)
        XCTAssertEqual(state.hsi.capacity?.value, 0.6)
        XCTAssertEqual(state.hsi.sleep?.value, 0.3)
        XCTAssertEqual(state.rawJson, json)
    }

    func testParsesFlatAxesJson() {
        let json = """
        {"focus":{"value":0.7,"confidence":0.8},"arousal":{"value":0.4,"confidence":0.6}}
        """
        let state = HSIState.fromJson(json, subjectId: "usr_ext")
        XCTAssertEqual(state.subjectId, "usr_ext")
        XCTAssertEqual(state.hsi.focus?.value, 0.7)
        XCTAssertEqual(state.hsi.arousal?.value, 0.4)
        XCTAssertNil(state.hsi.capacity)
        XCTAssertNil(state.hsi.sleep)
    }

    func testHandlesMalformedJson() {
        let state = HSIState.fromJson("not-json", subjectId: "usr_x")
        XCTAssertEqual(state.subjectId, "usr_x")
        XCTAssertEqual(state.rawJson, "not-json")
        XCTAssertNil(state.hsi.focus)
    }

    func testUsesObservedAtMsAsFallback() {
        let json = """
        {"observed_at_ms":1234567890000,"focus":{"value":0.5,"confidence":0.5}}
        """
        let state = HSIState.fromJson(json)
        XCTAssertEqual(state.timestampMs, 1234567890000)
    }
}
