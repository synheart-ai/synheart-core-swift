import XCTest
@testable import SynheartCore

final class ParityModelsTests: XCTestCase {
    func testSyncEnvelopeUnwrapsSuccessDataAndPreservesLegacyPayloads() {
        let success = CoreRuntimeBridge.unwrapSyncEnvelope([
            "ok": true,
            "data": ["configured": true, "state": "NO_ACTIVE_SPACE"],
        ])
        XCTAssertEqual(success?["configured"] as? Bool, true)
        XCTAssertEqual(success?["state"] as? String, "NO_ACTIVE_SPACE")

        let legacy = ["sync_space_id": "space-1"]
        XCTAssertEqual(
            CoreRuntimeBridge.unwrapSyncEnvelope(legacy)?["sync_space_id"] as? String,
            "space-1"
        )
    }

    func testSyncEnvelopePreservesNativeFailureDetail() {
        let result = CoreRuntimeBridge.unwrapSyncEnvelope([
            "ok": false,
            "error": [
                "code": "NETWORK",
                "message": "Network error",
                "retryable": true,
            ],
        ])
        XCTAssertEqual(result?["error"] as? String, "Network error")
        XCTAssertEqual(result?["code"] as? String, "NETWORK")
        XCTAssertEqual(result?["retryable"] as? Bool, true)
    }

    func testBaselineEnvelopeRoundTripsAndDecodesTypedAxes() throws {
        let header = ArtifactHeader(
            type: "baseline_snapshot",
            artifactId: "artifact-1",
            subjectId: "subject-1",
            sessionId: "session-1",
            timeRange: TimeRange(startMs: 100, endMs: 200),
            schema: SchemaRef(name: "baseline", version: "1")
        )
        let envelope = try BaselineEnvelope(
            header: header,
            kind: .sessionHsiAxes,
            kindSchemaVersion: 1,
            computedAtMs: 200,
            engine: BaselineEngineRef(name: "srm", version: "1", configHash: "sha256:test"),
            coverage: BaselineEnvelopeCoverage(
                windowStartMs: 100,
                windowEndMs: 200,
                observations: 12,
                dimensionsPresent: 1,
                dimensionsTotal: 4
            ),
            payload: HsiAxesBaseline(
                axes: ["focus": AxisStats(mean: 0.6, std: 0.1, confidence: 0.8)]
            ).toRuntimeMap()
        )

        let decoded = try BaselineEnvelope(runtimeMap: envelope.toRuntimeMap())

        XCTAssertEqual(decoded.kind, .sessionHsiAxes)
        XCTAssertEqual(try decoded.hsiAxes().axes["focus"]?.confidence, 0.8)
        XCTAssertThrowsError(try decoded.longitudinalWear())
    }

    func testBaselineEnvelopeEnforcesSessionScope() {
        let header = ArtifactHeader(
            type: "baseline_snapshot",
            subjectId: "subject-1",
            timeRange: TimeRange(startMs: 0, endMs: 1),
            schema: SchemaRef(name: "baseline", version: "1")
        )
        XCTAssertThrowsError(
            try BaselineEnvelope(
                header: header,
                kind: .sessionHsiAxes,
                kindSchemaVersion: 1,
                computedAtMs: 1,
                engine: BaselineEngineRef(name: "srm", version: "1", configHash: "hash"),
                coverage: BaselineEnvelopeCoverage(
                    windowStartMs: 0,
                    windowEndMs: 1,
                    observations: 1,
                    dimensionsPresent: 1,
                    dimensionsTotal: 1
                ),
                payload: [:]
            )
        )
    }

    func testBaselineCacheHydratesSupportedKindsAndSkipsUnknown() throws {
        let header = ArtifactHeader(
            type: "baseline_snapshot",
            subjectId: "subject-1",
            timeRange: TimeRange(startMs: 0, endMs: 1),
            schema: SchemaRef(name: "baseline", version: "1")
        )
        let wear = try BaselineEnvelope(
            header: header,
            kind: .longitudinalWear,
            kindSchemaVersion: 1,
            computedAtMs: 1,
            engine: BaselineEngineRef(name: "srm", version: "1", configHash: "hash"),
            coverage: BaselineEnvelopeCoverage(
                windowStartMs: 0,
                windowEndMs: 1,
                observations: 1,
                dimensionsPresent: 1,
                dimensionsTotal: 1
            ),
            payload: LongitudinalWearBaseline(
                reference: WearableReferenceView(status: "Ready", dimensions: ["hrv_rmssd_ms": 42])
            ).toRuntimeMap()
        )
        var unknown = try wear.toRuntimeMap()
        unknown["kind"] = "future.kind"
        let cache = BaselineSnapshots()

        let hydrated = cache.hydrate(from: ["snapshots": [try wear.toRuntimeMap(), unknown]])

        XCTAssertEqual(hydrated.count, 1)
        XCTAssertEqual(try cache.envelope(for: .longitudinalWear)?.longitudinalWear().reference.dimensions["hrv_rmssd_ms"], 42)
    }

    func testSyncReadinessFailsClosedForNativePrerequisites() {
        let missingRegistration = SyncReadiness.evaluate(
            operation: .syncNow,
            nativeSnapshot: [
                "configured": true,
                "storage_present": true,
                "device_registered": false,
            ]
        )
        XCTAssertFalse(missingRegistration.isReady)
        XCTAssertEqual(missingRegistration.code, .deviceRegistrationRequired)

        let ready = SyncReadiness.evaluate(
            operation: .syncNow,
            nativeSnapshot: [
                "configured": true,
                "storage_present": true,
                "device_registered": true,
                "active_space": true,
                "srk_ready": true,
            ]
        )
        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(ready.code, .ready)
    }

    func testDeletionModelParsesFractionalTimestampAndUnknownStatus() throws {
        let request = try DataDeletionRequest(runtimeMap: [
            "request_id": "ddr-1",
            "status": "queued_by_future_runtime",
            "created_at": "2026-09-01T10:11:12.345Z",
        ])
        XCTAssertEqual(request.status, .unknown)
        XCTAssertEqual(request.statusRaw, "queued_by_future_runtime")
        XCTAssertEqual(request.requestId, "ddr-1")
    }

    func testPersonalizationDiscriminantsAndVendorNormalization() {
        XCTAssertEqual(TaskType.focus.rawValue, 1)
        XCTAssertEqual(FocusKind.hard.rawValue, 3)
        XCTAssertEqual(WorkoutKind.sport.rawValue, 5)
        let event = WorkoutEvent(
            startTime: Date(timeIntervalSince1970: 1),
            endTime: Date(timeIntervalSince1970: 2),
            kind: .cardio,
            source: "test",
            vendorStrain: 2,
            vendorRecovery: 0.7
        )
        XCTAssertEqual(event.strainForRuntime, -1)
        XCTAssertEqual(event.recoveryForRuntime, 0.7)
    }

    func testVendorStreamConfigurationUsesCanonicalKeys() throws {
        let config = VendorStreamConfig(
            host: "stream.example",
            port: 443,
            appId: "app",
            deviceId: "device",
            userId: "user",
            providers: ["garmin"]
        )
        let data = try XCTUnwrap(config.jsonString()?.data(using: .utf8))
        let map = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(map["app_id"] as? String, "app")
        XCTAssertEqual(map["use_tls"] as? Bool, true)
        XCTAssertEqual(map["providers"] as? [String], ["garmin"])
    }
}
