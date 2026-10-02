import XCTest
@testable import SynheartCore

final class BehaviorEventInputTests: XCTestCase {
    private func decode(_ event: BehaviorEventInput) throws -> [String: Any] {
        let json = try XCTUnwrap(event.toJSONString())
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testEnvelopeCarriesTimestampKindAndValue() throws {
        let obj = try decode(.screenOff(1_700_000_000_000))
        XCTAssertEqual(obj["ts_ms"] as? Int64, 1_700_000_000_000)
        XCTAssertEqual(obj["kind"] as? String, "screen_off")
        XCTAssertEqual(obj["value"] as? Double, 0)
        XCTAssertNil(obj["data"], "kinds without a payload must not emit an empty data object")
    }

    func testTouchOmitsAbsentFields() throws {
        let obj = try decode(.touch(1, longPress: true))
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["long_press"] as? Bool, true)
        XCTAssertNil(data["duration_ms"])
    }

    func testScrollUsesLowercaseDirectionOnTheWire() throws {
        let obj = try decode(.scroll(5, velocity: 2.5, direction: .down, directionReversal: false))
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["direction"] as? String, "down")
        XCTAssertEqual(data["velocity"] as? Double, 2.5)
        XCTAssertEqual(data["direction_reversal"] as? Bool, false)
    }

    func testAppForegroundCarriesTheIdentifierOnly() throws {
        let obj = try decode(.appForeground(9, app: "com.example.reader"))
        XCTAssertEqual(obj["kind"] as? String, "app_foreground")
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data as? [String: String], ["app": "com.example.reader"])
    }

    func testNotificationAndCallActions() throws {
        let n = try decode(.notification(1, action: .dismissed, sourceApp: "com.example.mail"))
        let nd = try XCTUnwrap(n["data"] as? [String: Any])
        XCTAssertEqual(nd["action"] as? String, "dismissed")
        XCTAssertEqual(nd["source_app"] as? String, "com.example.mail")

        let c = try decode(.call(2, action: .answered))
        let cd = try XCTUnwrap(c["data"] as? [String: Any])
        XCTAssertEqual(cd["action"] as? String, "answered")
    }

    func testSystemFailureDurationRidesInValueAndData() throws {
        let obj = try decode(.systemFailure(3, durationSecs: 12.5))
        XCTAssertEqual(obj["value"] as? Double, 12.5)
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["duration_secs"] as? Double, 12.5)
    }

    func testTypingWindowSerialisesOnlyMeasuredFields() throws {
        let session = TypingSessionData(
            durationSec: 30,
            typingSpeedCpm: 210,
            typingTapCount: 105,
            deepTyping: true
        )
        let obj = try decode(.typing(windowStartMs: 60_000, session: session))
        XCTAssertEqual(obj["ts_ms"] as? Int64, 60_000)
        XCTAssertEqual(obj["kind"] as? String, "typing")
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["duration_sec"] as? Double, 30)
        XCTAssertEqual(data["typing_speed_cpm"] as? Double, 210)
        XCTAssertEqual(data["typing_tap_count"] as? Int, 105)
        XCTAssertEqual(data["deep_typing"] as? Bool, true)
        XCTAssertEqual(data.count, 4, "unmeasured fields must be absent, not zero")
    }

    func testTypingSessionDataWireKeysAreSnakeCase() {
        let all = TypingSessionData(
            durationSec: 1, typingSpeedCpm: 1, typingTapCount: 1, pauseCount: 1,
            meanInterTapIntervalMs: 1, typingCadenceStability: 1, typingCadenceVariability: 1,
            cadenceStability: 1, typingGapCount: 1, typingGapRatio: 1, typingBurstiness: 1,
            typingActivityRatio: 1, typingInteractionIntensity: 1, deepTyping: true,
            numberOfBackspace: 1, numberOfDelete: 1, numberOfCut: 1, numberOfPaste: 1,
            numberOfCopy: 1, keyboardScrollRate: 1, shortcutCount: 1, shortcutRate: 1,
            typingEfficiency: 1, holdTimeMean: 1, latencyVariability: 1
        ).toJSON()
        XCTAssertEqual(all.count, 25)
        for key in all.keys {
            XCTAssertEqual(key, key.lowercased(), "wire key \(key) must be snake_case")
            XCTAssertFalse(key.contains("-"))
        }
        XCTAssertNotNil(all["mean_inter_tap_interval_ms"])
        XCTAssertNotNil(all["number_of_backspace"])
    }

    func testEventsAreEquatable() {
        XCTAssertEqual(BehaviorEventInput.touch(1, durationMs: 40), .touch(1, durationMs: 40))
        XCTAssertNotEqual(BehaviorEventInput.touch(1, durationMs: 40), .touch(1, durationMs: 41))
    }
}
