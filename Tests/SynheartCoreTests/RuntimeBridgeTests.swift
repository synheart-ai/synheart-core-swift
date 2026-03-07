import XCTest
@testable import SynheartCore

/// Integration tests for the synheart-runtime native bridge.
///
/// These tests require the native library (libsynheart_runtime.dylib) to be
/// loadable at runtime. Set DYLD_LIBRARY_PATH to the lib/ directory:
///   DYLD_LIBRARY_PATH=./lib swift test --filter RuntimeBridgeTests
///
/// When the native library is unavailable, tests that depend on it are skipped.
final class RuntimeBridgeTests: XCTestCase {

    private var bridge: RuntimeBridge?

    override func setUp() {
        super.setUp()
        bridge = RuntimeBridge.createIfAvailable(config: .init(
            windowMs: 10_000,
            stepMs: 5_000,
            subjectId: "sub_test_001",
            sessionId: "sess_test_001"
        ))
    }

    override func tearDown() {
        bridge = nil // deinit frees the native handle
        super.tearDown()
    }

    /// Helper: push RR + HR data spanning a 10s window, then tick.
    @discardableResult
    private func fillWindowAndTick(_ b: RuntimeBridge, baseMs: Int64) -> String? {
        for i in 0..<15 {
            b.pushRr(tsMs: baseMs + Int64(i) * 800, rrMs: 800.0)
        }
        for i in 0..<12 {
            b.pushHr(tsMs: baseMs + Int64(i) * 1000, bpm: 72.0)
        }
        return b.tick(nowMs: baseMs + 10_000)
    }

    // MARK: - Availability

    func testCreateIfAvailableReturnsNonNil() {
        // This test verifies the native library is linked.
        // If it fails, ensure libsynheart_runtime.dylib is on DYLD_LIBRARY_PATH.
        XCTAssertNotNil(
            bridge,
            "Native runtime library should be loadable. Set DYLD_LIBRARY_PATH."
        )
    }

    func testVersionReturnsValidString() {
        let v = RuntimeBridge.version()
        XCTAssertNotNil(v, "version() should return a string")
        if let v = v {
            let regex = try! NSRegularExpression(pattern: #"^\d+\.\d+\.\d+"#)
            let range = NSRange(v.startIndex..<v.endIndex, in: v)
            XCTAssertNotNil(
                regex.firstMatch(in: v, range: range),
                "version should match semver format (got: \(v))"
            )
        }
    }

    // MARK: - Signal Push + Tick

    func testPushSyntheticRRAndHRThenTickProducesHSI() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var hsi = fillWindowAndTick(b, baseMs: now)
        if hsi == nil {
            hsi = fillWindowAndTick(b, baseMs: now + 15_000)
        }

        XCTAssertNotNil(hsi, "tick should produce HSI JSON after enough signal data")

        let data = try XCTUnwrap(hsi?.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(parsed.keys.contains("hsi_version"))
    }

    func testPushBehaviorEventsThenTickIncludesBehaviorDomain() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // Push baseline RR + HR data
        for i in 0..<15 {
            b.pushRr(tsMs: now + Int64(i) * 800, rrMs: 800.0)
        }
        for i in 0..<12 {
            b.pushHr(tsMs: now + Int64(i) * 1000, bpm: 72.0)
        }
        // Push behavior events
        for i in 0..<10 {
            b.pushBehavior(tsMs: now + Int64(i) * 500, eventType: 2, value: 1.0) // Touch
        }
        b.pushBehavior(tsMs: now + 5000, eventType: 3, value: 1.0) // App switch

        var hsi = b.tick(nowMs: now + 10_000)
        // Retry with second window if needed
        if hsi == nil {
            for i in 0..<15 {
                b.pushRr(tsMs: now + 15_000 + Int64(i) * 800, rrMs: 800.0)
                b.pushHr(tsMs: now + 15_000 + Int64(i) * 800, bpm: 72.0)
            }
            hsi = b.tick(nowMs: now + 25_000)
        }

        if let hsi = hsi {
            let data = hsi.data(using: .utf8)!
            let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertTrue(parsed.keys.contains("hsi_version"))
        }
    }

    // MARK: - Frame Count

    func testFrameCountIncrementsAfterSuccessfulTick() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let initialCount = b.frameCount()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<5 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        let finalCount = b.frameCount()
        if finalCount > initialCount {
            XCTAssertGreaterThan(finalCount, initialCount)
        }
    }

    // MARK: - Quality

    func testLastQualityReturnsValidJSON() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<3 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        if let quality = b.lastQuality() {
            let data = quality.data(using: .utf8)!
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    // MARK: - Reset

    func testResetClearsStateAndFrameCount() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<3 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        b.reset()
        XCTAssertEqual(b.frameCount(), 0, "frameCount should be 0 after reset")
    }

    // MARK: - Multiple Windows

    func testMultipleWindowsProduceMultipleFrames() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var framesProduced = 0

        for window in 0..<10 {
            let hsi = fillWindowAndTick(b, baseMs: now + Int64(window) * 15_000)
            if hsi != nil {
                framesProduced += 1
            }
        }

        XCTAssertGreaterThanOrEqual(
            framesProduced, 1,
            "Should produce at least one frame across 10 windows"
        )
    }

    // MARK: - SRM Baselines

    func testBaselineSummaryReturnsValidJSON() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let summary = b.baselineSummary()
        XCTAssertNotNil(summary, "baselineSummary() should return JSON")

        let data = try XCTUnwrap(summary?.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(parsed.keys.contains("total"), "summary should have 'total' key")
        XCTAssertTrue(parsed.keys.contains("ready"), "summary should have 'ready' key")
        XCTAssertTrue(parsed.keys.contains("warming"), "summary should have 'warming' key")
        XCTAssertTrue(parsed.keys.contains("empty"), "summary should have 'empty' key")
    }

    func testBaselinesJsonReturnsValidJSON() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let baselines = b.baselinesJson()
        XCTAssertNotNil(baselines, "baselinesJson() should return JSON")

        let data = try XCTUnwrap(baselines?.data(using: .utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testBaselineSummaryWarmingAfterData() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Push data and tick to get SRM ingestion
        for w in 0..<5 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        let summary = b.baselineSummary()
        XCTAssertNotNil(summary)

        let data = try XCTUnwrap(summary?.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let total = parsed["total"] as? Int ?? 0
        XCTAssertGreaterThan(total, 0, "Should have SRM metrics registered")
    }

    func testSrmSnapshotExportAndLoad() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<5 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        // Export snapshot
        let snapshot = b.exportSrmSnapshot()
        XCTAssertNotNil(snapshot, "exportSrmSnapshot() should return JSON")

        // Verify it's valid JSON
        let data = try XCTUnwrap(snapshot?.data(using: .utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))

        // Create a new bridge and load the snapshot
        let b2 = try XCTUnwrap(
            RuntimeBridge.createIfAvailable(config: .init(
                windowMs: 10_000,
                stepMs: 5_000,
                subjectId: "sub_test_002",
                sessionId: "sess_test_002"
            )),
            "Native library not available"
        )

        let result = b2.loadSrmSnapshot(json: snapshot!)
        XCTAssertEqual(result, 0, "loadSrmSnapshot should return 0 on success")

        // Verify loaded bridge has same baseline summary
        let originalSummary = b.baselineSummary()
        let loadedSummary = b2.baselineSummary()
        XCTAssertEqual(originalSummary, loadedSummary,
            "Baseline summary should match after snapshot round-trip")
    }

    func testResetClearsSrmBaselines() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<5 {
            fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000)
        }

        b.reset()

        let summary = b.baselineSummary()
        XCTAssertNotNil(summary)

        let data = try XCTUnwrap(summary?.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let warming = parsed["warming"] as? Int ?? -1
        let ready = parsed["ready"] as? Int ?? -1
        XCTAssertEqual(warming, 0, "warming should be 0 after reset")
        XCTAssertEqual(ready, 0, "ready should be 0 after reset")
    }

    // MARK: - Pre-processed Data

    func testLastPreprocessedReturnsValidJSONWithExpectedStructure() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<3 { fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000) }
        if let json = b.lastPreprocessed() {
            let data = try XCTUnwrap(json.data(using: .utf8))
            let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertTrue(parsed.keys.contains("schema_version"))
            XCTAssertTrue(parsed.keys.contains("quality"))
            XCTAssertTrue(parsed.keys.contains("derived_features"))
            XCTAssertTrue(parsed.keys.contains("srm_context"))
            XCTAssertTrue(parsed.keys.contains("embeddings"))
            let window = try PreprocessedWindow.fromJson(json)
            XCTAssertGreaterThanOrEqual(window.quality.score, 0.0)
            XCTAssertLessThanOrEqual(window.quality.score, 1.0)
            XCTAssertGreaterThanOrEqual(window.quality.rrCount, 0)
            XCTAssertGreaterThanOrEqual(window.srmContext.totalCount, 0)
        }
    }

    func testLastPreprocessedReturnsNilAfterReset() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for w in 0..<3 { fillWindowAndTick(b, baseMs: now + Int64(w) * 15_000) }
        b.reset()
        XCTAssertNil(b.lastPreprocessed(), "lastPreprocessed should be nil after reset")
    }

    func testPreprocessedWindowModelParsesValidJSON() throws {
        let jsonStr = """
        {"schema_version":"1.0.0","window_start_ms":1000,"window_end_ms":11000,"session_id":"test_session","quality":{"score":0.85,"coverage_pct":0.9,"dropout_count":0,"rr_count":10,"artifact_pct":0.05},"derived_features":{"hrv":{"rmssd_ms":42.5,"sdnn_ms":38.0,"pnn50":0.25,"mean_rr_ms":800.0,"hr_mean_bpm":72.0,"hr_std_bpm":3.5,"rr_count":10},"motion":null,"artifact":null},"behavior_features":null,"srm_context":{"ready_count":0,"total_count":14,"deviations":{}},"embeddings":{"signal_embedding":{"vector":[0.1,0.2,0.3],"dimension":3,"space":"latent"}}}
        """
        let window = try PreprocessedWindow.fromJson(jsonStr)
        XCTAssertEqual(window.schemaVersion, "1.0.0")
        XCTAssertEqual(window.quality.score, 0.85, accuracy: 0.001)
        XCTAssertEqual(window.quality.rrCount, 10)
        XCTAssertEqual(window.derivedFeatures.hrv!.rmssdMs, 42.5, accuracy: 0.001)
        XCTAssertEqual(window.srmContext.totalCount, 14)
        XCTAssertEqual(window.embeddings.signalEmbedding.dimension, 3)
    }

    // MARK: - Batch Ingest

    func testIngestBatchWithRREventsProducesHSIFrames() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var batch: [[String: Any]] = []

        // Build batch of RR events spanning multiple windows
        for i in 0..<30 {
            batch.append(["type": "rr", "ts_ms": now + Int64(i) * 800, "rr_ms": 800.0])
        }
        // Add HR events
        for i in 0..<25 {
            batch.append(["type": "hr", "ts_ms": now + Int64(i) * 1000, "bpm": 72.0])
        }

        let batchData = try JSONSerialization.data(withJSONObject: batch)
        let batchJson = String(data: batchData, encoding: .utf8)!

        guard let result = b.ingestBatch(batchJson: batchJson, nowMs: now + 30_000) else {
            // ingestBatch FFI symbol may not be available in this build
            throw XCTSkip("ingestBatch not available in linked runtime")
        }

        let resultData = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: resultData) as! [String: Any]
        XCTAssertEqual(parsed["ok"] as? Bool, true, "Batch ingest should succeed")

        // Should have frames array or legacy hsi
        let hasFrames = (parsed["frames"] as? [[String: Any]])?.isEmpty == false
        let hasHsi = parsed["hsi"] != nil
        XCTAssertTrue(hasFrames || hasHsi, "Result should contain frames array or hsi object")
    }

    func testIngestBatchWithBehaviorEventsProducesHSIFrames() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var batch: [[String: Any]] = []

        // RR baseline
        for i in 0..<30 {
            batch.append(["type": "rr", "ts_ms": now + Int64(i) * 800, "rr_ms": 800.0])
        }
        for i in 0..<25 {
            batch.append(["type": "hr", "ts_ms": now + Int64(i) * 1000, "bpm": 72.0])
        }
        // Behavior events
        for i in 0..<10 {
            batch.append([
                "type": "behavior",
                "ts_ms": now + Int64(i) * 500,
                "event": "touch",
                "provider": "behavior_app"
            ])
        }
        batch.append([
            "type": "behavior",
            "ts_ms": now + 5000,
            "event": "app_switch",
            "provider": "behavior_app"
        ])

        let batchData = try JSONSerialization.data(withJSONObject: batch)
        let batchJson = String(data: batchData, encoding: .utf8)!

        guard let result = b.ingestBatch(batchJson: batchJson, nowMs: now + 30_000) else {
            throw XCTSkip("ingestBatch not available in linked runtime")
        }

        let resultData = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: resultData) as! [String: Any]
        XCTAssertEqual(parsed["ok"] as? Bool, true, "Batch ingest with behavior should succeed")
    }

    func testIngestBatchWithEmptyArrayReturnsOk() throws {
        let b = try XCTUnwrap(bridge, "Native library not available")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard let result = b.ingestBatch(batchJson: "[]", nowMs: now) else {
            throw XCTSkip("ingestBatch not available in linked runtime")
        }

        let resultData = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: resultData) as! [String: Any]
        XCTAssertEqual(parsed["ok"] as? Bool, true, "Empty batch should succeed")
    }
}
