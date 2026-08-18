import XCTest
@testable import SynheartCore

final class HSIStateTests: XCTestCase {

    func testParsesNestedHSIJson() {
        let json = """
        {"subject_id":"usr_123","timestamp_ms":1700000000000,"hsi":{"focus":{"value":0.8,"confidence":0.9},"arousal":{"value":0.5,"confidence":0.7},"capacity":{"value":0.6,"confidence":0.8},"sleep":{"value":0.3,"confidence":0.95},"stress":{"value":0.38,"confidence":0.55}}}
        """
        let state = HSIState.fromJson(json)
        XCTAssertEqual(state.subjectId, "usr_123")
        XCTAssertEqual(state.timestampMs, 1700000000000)
        XCTAssertEqual(state.hsi.focus?.value, 0.8)
        XCTAssertEqual(state.hsi.focus?.confidence, 0.9)
        XCTAssertEqual(state.hsi.arousal?.value, 0.5)
        XCTAssertEqual(state.hsi.capacity?.value, 0.6)
        XCTAssertEqual(state.hsi.sleep?.value, 0.3)
        XCTAssertEqual(state.hsi.stress?.value, 0.38)
        XCTAssertEqual(state.hsi.stress?.confidence, 0.55)
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
        XCTAssertNil(state.hsi.stress)
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

    func testParsesCanonicalHSI13DomainsAndIdentity() {
        let json = """
        {
          "hsi_version":"1.3",
          "subject_id":"usr_v13",
          "observed_at_utc":"2026-05-01T09:01:00Z",
          "axes":{
            "cognitive":[
              {"name":"focus","score":0.71,"confidence":0.6},
              {"name":"capacity","score":0.55,"confidence":0.58}
            ],
            "affective":[
              {"name":"arousal","score":0.45,"confidence":0.5},
              {"name":"stress","score":0.38,"confidence":0.55}
            ],
            "physiological":[
              {"name":"sleep_score","score":0.42,"confidence":0.9}
            ]
          },
          "meta":{
            "ids":{"hsi_id":"window-v13"},
            "provenance":{"sources":{
              "watch":{"signals":["hrv","accel"],"source_tier":2},
              "phone":{"signals":["touch"]}
            }},
            "synheart":{"tiers":{"kinematic":1,"digital":3}}
          }
        }
        """

        let state = HSIState.fromJson(json)

        XCTAssertEqual(state.hsiVersion, "1.3")
        XCTAssertEqual(state.hsiId, "window-v13")
        XCTAssertEqual(state.subjectId, "usr_v13")
        XCTAssertEqual(state.timestampMs, 1_777_626_060_000)
        XCTAssertEqual(state.hsi.focus?.value, 0.71)
        XCTAssertEqual(state.hsi.capacity?.value, 0.55)
        XCTAssertEqual(state.hsi.arousal?.value, 0.45)
        XCTAssertEqual(state.hsi.stress?.value, 0.38)
        XCTAssertEqual(state.hsi.sleep?.value, 0.42)
        XCTAssertTrue(state.modalities.physiological)
        XCTAssertTrue(state.modalities.kinematic)
        XCTAssertTrue(state.modalities.digital)
        XCTAssertEqual(state.tiers.physiological, 2)
        XCTAssertEqual(state.tiers.kinematic, 1)
        XCTAssertEqual(state.tiers.digital, 3)
    }

    func testCanonicalNullScoreDoesNotBecomeZero() {
        let json = """
        {"hsi_version":"1.3","axes":{"cognitive":[
          {"name":"focus","score":null,"confidence":0.5}
        ]}}
        """

        XCTAssertNil(HSIState.fromJson(json).hsi.focus)
    }

    func testCanonicalPayloadNeverFallsBackToLegacyAxes() {
        let json = """
        {"hsi_version":"1.3","hsi":{"focus":{"value":0.99,"confidence":1}},
         "axes":{"cognitive":[{"name":"focus","score":0.5,"confidence":0.4}]}}
        """

        XCTAssertEqual(HSIState.fromJson(json).hsi.focus?.value, 0.5)
    }
}
