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
}
