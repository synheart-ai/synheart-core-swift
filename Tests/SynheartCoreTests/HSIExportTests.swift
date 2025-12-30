import XCTest
@testable import SynheartCore

final class HSIExportTests: XCTestCase {
    func testToHSI10_RequiredTopLevelFieldsPresent() throws {
        let meta = MetaState(
            device: DeviceInfo(platform: "ios", osVersion: "1.0", deviceModel: "TestDevice", deviceId: "dev"),
            sessionId: "sess-123",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            embeddings: nil
        )

        let hsv = HumanStateVector(
            heartRate: 72,
            heartRateVariability: nil,
            rmssd: nil,
            sdnn: nil,
            behavior: nil,
            context: nil,
            emotion: nil,
            focus: nil,
            meta: meta,
            hsiEmbedding: nil
        )

        let payload = hsv.toHSI10(
            producerName: "Synheart Core SDK",
            producerVersion: "1.0.0",
            instanceId: "instance_abcdef123456"
        )

        XCTAssertEqual(payload["hsi_version"] as? String, "1.0")
        XCTAssertEqual(payload["timestamp"] as? Int, 1_700_000_000)
        XCTAssertEqual(payload["window_type"] as? String, "micro")

        let producer = try XCTUnwrap(payload["producer"] as? [String: Any])
        XCTAssertEqual(producer["name"] as? String, "Synheart Core SDK")
        XCTAssertEqual(producer["version"] as? String, "1.0.0")
        XCTAssertEqual(producer["instance_id"] as? String, "instance_abcdef123456")

        let subject = try XCTUnwrap(payload["subject"] as? [String: Any])
        XCTAssertEqual(subject["subject_type"] as? String, "pseudonymous_user")
        // subject_id is derived from the first 8 chars of instanceId
        XCTAssertEqual(subject["subject_id"] as? String, "anon_instance")

        let privacy = try XCTUnwrap(payload["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["contains_pii"] as? Bool, false)
        XCTAssertEqual(privacy["derived_only"] as? Bool, true)
        XCTAssertEqual(privacy["aggregation_window_sec"] as? Int, 30)

        let device = try XCTUnwrap(payload["device"] as? [String: Any])
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(device["os_version"] as? String, "1.0")
        XCTAssertEqual(device["device_model"] as? String, "TestDevice")

        let metaOut = try XCTUnwrap(payload["meta"] as? [String: Any])
        XCTAssertEqual(metaOut["session_id"] as? String, "sess-123")

        XCTAssertNotNil(payload["state"] as? [String: Any])
    }

    func testToHSI10_IncludesOptionalStateSectionsOnlyWhenPresent() throws {
        let meta = MetaState(
            device: DeviceInfo(platform: "ios", osVersion: "1.0", deviceModel: "TestDevice", deviceId: "dev"),
            sessionId: "sess-123",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            embeddings: nil
        )

        var hsv = HumanStateVector(
            heartRate: nil,
            heartRateVariability: nil,
            rmssd: nil,
            sdnn: nil,
            behavior: nil,
            context: nil,
            emotion: nil,
            focus: nil,
            meta: meta,
            hsiEmbedding: nil
        )

        // With nothing set, state should not contain optional sections
        var payload = hsv.toHSI10(producerName: "p", producerVersion: "v", instanceId: "instance_abcdef123456")
        var state = try XCTUnwrap(payload["state"] as? [String: Any])
        XCTAssertNil(state["behavior"])
        XCTAssertNil(state["context"])
        XCTAssertNil(state["emotion"])
        XCTAssertNil(state["focus"])
        XCTAssertNil(state["embedding"])

        // Add behavior + context + embedding
        hsv.behavior = BehaviorState(typingRate: 1.2, scrollingRate: nil, appSwitchRate: 0.3, interactionIntensity: nil)
        hsv.context = ContextState(
            conversation: ConversationContext(isInConversation: true, conversationDuration: 10, lastInteractionTime: Date(timeIntervalSince1970: 1_700_000_001)),
            device: DeviceStateContext(isCharging: true, batteryLevel: 0.5, isScreenOn: false, networkType: "wifi"),
            patterns: UserPatternsContext(timeOfDay: 123, dayOfWeek: 2, activityPattern: "work")
        )
        hsv.hsiEmbedding = Array(repeating: 0.1, count: 64)

        payload = hsv.toHSI10(producerName: "p", producerVersion: "v", instanceId: "instance_abcdef123456")
        state = try XCTUnwrap(payload["state"] as? [String: Any])

        let behavior = try XCTUnwrap(state["behavior"] as? [String: Any])
        XCTAssertEqual(behavior["typing_rate"] as? Float, 1.2)
        XCTAssertEqual(behavior["app_switch_rate"] as? Float, 0.3)
        XCTAssertNil(behavior["scrolling_rate"])

        let context = try XCTUnwrap(state["context"] as? [String: Any])
        XCTAssertNotNil(context["conversation"] as? [String: Any])
        XCTAssertNotNil(context["device_state"] as? [String: Any])
        XCTAssertNotNil(context["patterns"] as? [String: Any])

        let embedding = try XCTUnwrap(state["embedding"] as? [Float])
        XCTAssertEqual(embedding.count, 64)
    }
}


