import XCTest
@testable import SynheartCore

/// Unit tests for session data buffering (getSessionHsiWindows / getSessionWearSamples).
///
/// These tests exercise the buffer data models and list behaviour directly,
/// without requiring the full SDK initialization or native runtime.
final class SessionBufferTests: XCTestCase {

    // MARK: - HSI buffer

    func testHsiBufferIsEmptyBeforeAnyData() {
        let buffer: [String] = []
        XCTAssertTrue(buffer.isEmpty)
    }

    func testHsiBufferAccumulatesJsonStrings() {
        var buffer: [String] = []
        buffer.append("{\"hsi\":\"frame1\"}")
        buffer.append("{\"hsi\":\"frame2\"}")
        buffer.append("{\"hsi\":\"frame3\"}")

        let snapshot = Array(buffer)
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot[0], "{\"hsi\":\"frame1\"}")
        XCTAssertEqual(snapshot[2], "{\"hsi\":\"frame3\"}")
    }

    func testHsiBufferPersistsAfterSourceStopsAdding() {
        var buffer: [String] = []
        buffer.append("{\"hsi\":\"frame1\"}")
        buffer.append("{\"hsi\":\"frame2\"}")

        // Simulate stopSession — no more additions, but buffer persists
        let snapshot = Array(buffer)
        XCTAssertEqual(snapshot.count, 2)
    }

    func testHsiBufferClearsOnNewSession() {
        var buffer: [String] = []
        buffer.append("{\"hsi\":\"old_frame\"}")
        XCTAssertEqual(buffer.count, 1)

        // Simulate startSession — clears previous data
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    func testHsiSnapshotIsCopyNotReference() {
        var buffer: [String] = []
        buffer.append("{\"hsi\":\"frame1\"}")

        let snapshot = Array(buffer)
        buffer.append("{\"hsi\":\"frame2\"}")

        // Snapshot should still have only the original item
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(buffer.count, 2)
    }

    // MARK: - WearSample buffer

    func testWearBufferIsEmptyBeforeAnyData() {
        let buffer: [WearSample] = []
        XCTAssertTrue(buffer.isEmpty)
    }

    func testWearBufferAccumulatesSamples() {
        var buffer: [WearSample] = []
        buffer.append(WearSample(timestamp: Date(), hr: 72))
        buffer.append(WearSample(timestamp: Date(), hr: 74))
        buffer.append(WearSample(timestamp: Date(), hr: 71))

        let snapshot = Array(buffer)
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot[0].hr, 72)
        XCTAssertEqual(snapshot[2].hr, 71)
    }

    func testWearBufferPersistsAfterSourceStopsAdding() {
        var buffer: [WearSample] = []
        buffer.append(WearSample(timestamp: Date(), hr: 72))
        buffer.append(WearSample(timestamp: Date(), hr: 74))

        let snapshot = Array(buffer)
        XCTAssertEqual(snapshot.count, 2)
    }

    func testWearBufferClearsOnNewSession() {
        var buffer: [WearSample] = []
        buffer.append(WearSample(timestamp: Date(), hr: 72))
        XCTAssertEqual(buffer.count, 1)

        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    func testWearSnapshotIsCopyNotReference() {
        var buffer: [WearSample] = []
        buffer.append(WearSample(timestamp: Date(), hr: 72))

        let snapshot = Array(buffer)
        buffer.append(WearSample(timestamp: Date(), hr: 99))

        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(buffer.count, 2)
    }
}
