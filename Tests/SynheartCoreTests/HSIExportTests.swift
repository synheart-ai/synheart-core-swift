import XCTest
@testable import SynheartCore

final class HSIExportTests: XCTestCase {

    private func makeMeta(timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> MetaState {
        MetaState(
            device: DeviceInfo(platform: "ios", osVersion: "17.0", deviceModel: "TestDevice", deviceId: "dev"),
            sessionId: "sess-123",
            timestamp: timestamp,
            embeddings: nil
        )
    }

    // MARK: - Top-level fields

    func testFluxBridgeExport_RequiredTopLevelFieldsPresent() throws {
        let hsv = HumanStateVector(meta: makeMeta())

        let payload = FluxBridge.export(
            hsv: hsv,
            producerName: "Synheart Core SDK",
            producerVersion: "1.0.0",
            instanceId: "instance-abc"
        ).payload

        XCTAssertEqual(payload["hsi_version"] as? String, "1.0")

        // observed_at_utc should be RFC3339, not epoch
        let observed = try XCTUnwrap(payload["observed_at_utc"] as? String)
        XCTAssertTrue(observed.contains("2023-11-14"), "Expected ISO8601 date, got: \(observed)")
        XCTAssertNotNil(payload["computed_at_utc"] as? String)

        // Producer
        let producer = try XCTUnwrap(payload["producer"] as? [String: Any])
        XCTAssertEqual(producer["name"] as? String, "Synheart Core SDK")
        XCTAssertEqual(producer["version"] as? String, "1.0.0")
        XCTAssertEqual(producer["instance_id"] as? String, "instance-abc")

        // Window IDs
        let windowIds = try XCTUnwrap(payload["window_ids"] as? [String])
        XCTAssertEqual(windowIds, ["w1"])

        // Windows map
        let windows = try XCTUnwrap(payload["windows"] as? [String: Any])
        let w1 = try XCTUnwrap(windows["w1"] as? [String: Any])
        XCTAssertNotNil(w1["start"] as? String)
        XCTAssertNotNil(w1["end"] as? String)
        XCTAssertEqual(w1["label"] as? String, "micro")

        // Privacy (canonical field names)
        let privacy = try XCTUnwrap(payload["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["contains_pii"] as? Bool, false)
        XCTAssertEqual(privacy["raw_biosignals_allowed"] as? Bool, false)
        XCTAssertEqual(privacy["derived_metrics_allowed"] as? Bool, true)
        XCTAssertEqual(privacy["consent"] as? String, "explicit")

        // Meta
        let metaOut = try XCTUnwrap(payload["meta"] as? [String: Any])
        XCTAssertEqual(metaOut["session_id"] as? String, "sess-123")
        XCTAssertEqual(metaOut["platform"] as? String, "ios")
        XCTAssertEqual(metaOut["sdk_version"] as? String, "1.0.0")

        // Non-standard fields must be absent
        XCTAssertNil(payload["timestamp"])
        XCTAssertNil(payload["window_type"])
        XCTAssertNil(payload["subject"])
        XCTAssertNil(payload["device"])
        XCTAssertNil(payload["state"])
    }

    // MARK: - Axes

    func testFluxBridgeExport_AxesEmittedWithEmotionAndFocus() throws {
        let hsv = HumanStateVector(
            emotion: EmotionState(stress: 0.6, calm: 0.3, engagement: 0.7, activation: 0.5, valence: -0.2),
            focus: FocusState(score: 0.8, cognitiveLoad: 0.4, clarity: 0.9, distraction: 0.1),
            meta: makeMeta()
        )

        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i").payload
        let axes = try XCTUnwrap(payload["axes"] as? [String: Any])

        // Affect domain
        let affect = try XCTUnwrap(axes["affect"] as? [String: Any])
        let affectReadings = try XCTUnwrap(affect["readings"] as? [[String: Any]])
        XCTAssertEqual(affectReadings.count, 4)
        let stressReading = try XCTUnwrap(affectReadings.first { ($0["axis"] as? String) == "stress" })
        let stressScore = try XCTUnwrap(stressReading["score"] as? Double)
        XCTAssertEqual(stressScore, 0.6, accuracy: 0.01)
        XCTAssertEqual(stressReading["window_id"] as? String, "w1")
        XCTAssertEqual(stressReading["direction"] as? String, "higher_is_more")

        // Valence should be remapped from [-1,1] to [0,1]: (-0.2 + 1) / 2 = 0.4
        let valenceReading = try XCTUnwrap(affectReadings.first { ($0["axis"] as? String) == "valence" })
        let valenceScore = try XCTUnwrap(valenceReading["score"] as? Double)
        XCTAssertEqual(valenceScore, 0.4, accuracy: 0.01)
        XCTAssertEqual(valenceReading["direction"] as? String, "bidirectional")

        // Engagement domain
        let engagement = try XCTUnwrap(axes["engagement"] as? [String: Any])
        let engReadings = try XCTUnwrap(engagement["readings"] as? [[String: Any]])
        XCTAssertEqual(engReadings.count, 4)
        let focusReading = try XCTUnwrap(engReadings.first { ($0["axis"] as? String) == "focus_score" })
        let focusScore = try XCTUnwrap(focusReading["score"] as? Double)
        XCTAssertEqual(focusScore, 0.8, accuracy: 0.01)

        // Behavior domain (no behavior state set, but domain should still exist with null readings)
        let behavior = try XCTUnwrap(axes["behavior"] as? [String: Any])
        let behReadings = try XCTUnwrap(behavior["readings"] as? [[String: Any]])
        XCTAssertEqual(behReadings.count, 1)
    }

    func testFluxBridgeExport_NoAxesWhenNothingSet() throws {
        let hsv = HumanStateVector(meta: makeMeta())
        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i").payload

        // Axes should still be present (null readings are explicit) since domains are always emitted
        let axes = try XCTUnwrap(payload["axes"] as? [String: Any])
        XCTAssertNotNil(axes["affect"])
        XCTAssertNotNil(axes["engagement"])
        XCTAssertNotNil(axes["behavior"])
    }

    // MARK: - Embeddings

    func testFluxBridgeExport_EmbeddingsIncludedWithVectorHash() throws {
        let embedding = Array(repeating: Float(0.1), count: 64)
        let hsv = HumanStateVector(meta: makeMeta(), hsiEmbedding: embedding)

        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i").payload

        let embeddings = try XCTUnwrap(payload["embeddings"] as? [[String: Any]])
        XCTAssertEqual(embeddings.count, 1)

        let emb = embeddings[0]
        XCTAssertEqual(emb["window_id"] as? String, "w1")
        XCTAssertEqual(emb["dimension"] as? Int, 64)
        XCTAssertEqual(emb["encoding"] as? String, "float32")
        XCTAssertEqual(emb["model"] as? String, "hsi-fusion-v1")

        let vectorHash = try XCTUnwrap(emb["vector_hash"] as? String)
        XCTAssertTrue(vectorHash.hasPrefix("sha256:"))

        // embedding_allowed in privacy should be true
        let privacy = try XCTUnwrap(payload["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["embedding_allowed"] as? Bool, true)
    }

    func testFluxBridgeExport_NoEmbeddingsWhenNil() throws {
        let hsv = HumanStateVector(meta: makeMeta())
        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i").payload

        XCTAssertNil(payload["embeddings"])

        let privacy = try XCTUnwrap(payload["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["embedding_allowed"] as? Bool, false)
    }

    // MARK: - Access control gating

    func testFluxBridgeExport_AccessControlDeniesEmotionAxes() throws {
        let hsv = HumanStateVector(
            emotion: EmotionState(stress: 0.6, calm: 0.3, engagement: 0.7, activation: 0.5, valence: 0.0),
            meta: makeMeta()
        )

        let access = HSIExportAccessContext(
            capabilityHsi: "core",
            capabilityCloud: "core",
            consentBiosignals: false,       // denied
            consentPhoneContext: false,
            consentBehavior: true,
            consentCloudUpload: true,
            consentEmotionEstimation: true,
            consentFocusEstimation: true
        )

        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i", access: access).payload
        let axes = try XCTUnwrap(payload["axes"] as? [String: Any])
        let affect = try XCTUnwrap(axes["affect"] as? [String: Any])
        let readings = try XCTUnwrap(affect["readings"] as? [[String: Any]])

        // All affect readings should have null scores with denial notes
        for reading in readings {
            XCTAssertTrue(reading["score"] is NSNull, "Expected null score for denied emotion axis '\(reading["axis"] ?? "")'")
            let notes = try XCTUnwrap(reading["notes"] as? String)
            XCTAssertTrue(notes.contains("consent_denied"))
        }

        // Meta should contain access context fields
        let metaOut = try XCTUnwrap(payload["meta"] as? [String: Any])
        XCTAssertEqual(metaOut["capability_hsi"] as? String, "core")
        XCTAssertEqual(metaOut["consent_biosignals"] as? Bool, false)
    }

    func testFluxBridgeExport_CapabilityNoneDeniesEverything() throws {
        let embedding = Array(repeating: Float(0.1), count: 64)
        let hsv = HumanStateVector(
            emotion: EmotionState(stress: 0.6, calm: 0.3, engagement: 0.7, activation: 0.5, valence: 0.0),
            focus: FocusState(score: 0.8, cognitiveLoad: 0.4, clarity: 0.9, distraction: 0.1),
            meta: makeMeta(),
            hsiEmbedding: embedding
        )

        let access = HSIExportAccessContext(
            capabilityHsi: "none",
            capabilityCloud: "none",
            consentBiosignals: true,
            consentPhoneContext: true,
            consentBehavior: true,
            consentCloudUpload: true,
            consentEmotionEstimation: true,
            consentFocusEstimation: true
        )

        let payload = FluxBridge.export(hsv: hsv, producerName: "p", producerVersion: "v", instanceId: "i", access: access).payload

        // Embedding should be suppressed
        XCTAssertNil(payload["embeddings"])

        // All axis scores should be null with capability_insufficient reason
        let axes = try XCTUnwrap(payload["axes"] as? [String: Any])
        for (_, domain) in axes {
            let domainDict = try XCTUnwrap(domain as? [String: Any])
            let readings = try XCTUnwrap(domainDict["readings"] as? [[String: Any]])
            for reading in readings {
                XCTAssertTrue(reading["score"] is NSNull)
                let notes = try XCTUnwrap(reading["notes"] as? String)
                XCTAssertTrue(notes.contains("capability_insufficient"))
            }
        }
    }

    // MARK: - Window parameters

    func testFluxBridgeExport_CustomWindowParameters() throws {
        let hsv = HumanStateVector(meta: makeMeta())
        let payload = FluxBridge.export(
            hsv: hsv,
            producerName: "p",
            producerVersion: "v",
            instanceId: "i",
            windowLabel: "short",
            windowDurationSeconds: 300
        ).payload

        let windows = try XCTUnwrap(payload["windows"] as? [String: Any])
        let w1 = try XCTUnwrap(windows["w1"] as? [String: Any])
        XCTAssertEqual(w1["label"] as? String, "short")

        // Window start should be 300s before end
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let start = try XCTUnwrap(iso.date(from: w1["start"] as! String))
        let end = try XCTUnwrap(iso.date(from: w1["end"] as! String))
        XCTAssertEqual(end.timeIntervalSince(start), 300, accuracy: 1)
    }

    // MARK: - Backwards compatibility

    func testFluxBridgeExport_BackwardsCompatible3ParamCall() throws {
        let hsv = HumanStateVector(meta: makeMeta())

        // FluxBridge.export() with just 3 params (defaults for window)
        let snapshot = FluxBridge.export(
            hsv: hsv,
            producerName: "Synheart Core SDK",
            producerVersion: "1.0.0",
            instanceId: "instance-abc"
        )

        XCTAssertEqual(snapshot.hsiVersion, "1.0")
        XCTAssertNotNil(snapshot.observedAtUtc)
        XCTAssertNotNil(snapshot.computedAtUtc)
    }
}
