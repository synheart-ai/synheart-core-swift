import XCTest
@testable import SynheartCore

final class StoragePolicyTests: XCTestCase {

    // MARK: - Personal mode

    func testPersonalAllowsBaselineAndSession() {
        let policy = storagePolicyForMode(.personal)
        XCTAssertTrue(policy.canPersistArtifact("hsi_window"))
        XCTAssertTrue(policy.canPersistArtifact("session_summary"))
        XCTAssertTrue(policy.canPersistArtifact("baseline_snapshot"))
        XCTAssertTrue(policy.canPersistArtifact("tombstone"))
    }

    func testPersonalRejectsBioStreams() {
        let policy = storagePolicyForMode(.personal)
        XCTAssertFalse(policy.canPersistStream("hrv_raw"))
        XCTAssertFalse(policy.canPersistStream("ppg_raw"))
        XCTAssertFalse(policy.canPersistStream("accel_raw"))
    }

    func testPersonalRejectsMetrics() {
        let policy = storagePolicyForMode(.personal)
        XCTAssertFalse(policy.canIncludeMetrics())
    }

    // MARK: - Insight mode

    func testInsightAllowsAllArtifacts() {
        let policy = storagePolicyForMode(.insight)
        XCTAssertTrue(policy.canPersistArtifact("hsi_window"))
        XCTAssertTrue(policy.canPersistArtifact("session_summary"))
        XCTAssertTrue(policy.canPersistArtifact("baseline_snapshot"))
        XCTAssertTrue(policy.canPersistArtifact("tombstone"))
    }

    func testInsightRejectsBioStreams() {
        let policy = storagePolicyForMode(.insight)
        XCTAssertFalse(policy.canPersistStream("hrv_raw"))
        XCTAssertFalse(policy.canPersistStream("ppg_raw"))
    }

    func testInsightAllowsMetrics() {
        let policy = storagePolicyForMode(.insight)
        XCTAssertTrue(policy.canIncludeMetrics())
    }

    // MARK: - Research mode

    func testResearchAllowsAll() {
        let policy = storagePolicyForMode(.research)
        XCTAssertTrue(policy.canPersistArtifact("hsi_window"))
        XCTAssertTrue(policy.canPersistArtifact("session_summary"))
        XCTAssertTrue(policy.canPersistArtifact("baseline_snapshot"))
        XCTAssertTrue(policy.canPersistArtifact("tombstone"))
        XCTAssertTrue(policy.canPersistStream("hrv_raw"))
        XCTAssertTrue(policy.canPersistStream("ppg_raw"))
        XCTAssertTrue(policy.canPersistStream("accel_raw"))
        XCTAssertTrue(policy.canIncludeMetrics())
    }

    // MARK: - Unknown artifact type

    func testUnknownArtifactTypeRejected() {
        let policy = storagePolicyForMode(.personal)
        XCTAssertFalse(policy.canPersistArtifact("unknown_type"))
    }
}
