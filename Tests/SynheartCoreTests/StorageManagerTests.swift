import XCTest
@testable import SynheartCore

final class StorageManagerTests: XCTestCase {

    private var sm: StorageManager!
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "synheart_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        sm = StorageManager(basePath: tempDir)
        try! sm.open()
    }

    override func tearDown() {
        sm.close()
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    // MARK: - Sessions

    func testInsertAndListSessions() throws {
        try sm.insertSession(SessionRecord(
            sessionId: "s1", subjectId: "usr_1", mode: "personal",
            createdAtUtc: 1000, startUtc: 1000,
            appId: "app", appVersion: "1.0", deviceId: "d1", platform: "ios"
        ))
        try sm.insertSession(SessionRecord(
            sessionId: "s2", subjectId: "usr_1", mode: "insight",
            createdAtUtc: 2000, startUtc: 2000,
            appId: "app", appVersion: "1.0", deviceId: "d1", platform: "ios"
        ))

        let sessions = try sm.listSessions()
        XCTAssertEqual(sessions.count, 2)
    }

    func testUpdateSession() throws {
        try sm.insertSession(SessionRecord(
            sessionId: "s1", subjectId: "usr_1", mode: "personal",
            createdAtUtc: 1000, startUtc: 1000,
            appId: "app", appVersion: "1.0", deviceId: "d1", platform: "ios"
        ))

        try sm.updateSession("s1", state: "closed", endUtc: 2000)

        let sessions = try sm.listSessions()
        XCTAssertEqual(sessions.first?.state, "closed")
        XCTAssertEqual(sessions.first?.endUtc, 2000)
    }

    // MARK: - Artifacts

    func testInsertAndGetArtifact() throws {
        let record = ArtifactRecord(
            artifactId: "art_1", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 1000, endMs: 2000, seq: 0, createdAtMs: 1000,
            encAlg: "chacha20poly1305",
            payload: Data([0x01, 0x02]), payloadSha256: "abc123"
        )
        try sm.insertArtifact(record)

        let fetched = try sm.getArtifact("art_1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.artifactId, "art_1")
        XCTAssertEqual(fetched?.type, "hsi_window")
        XCTAssertEqual(fetched?.payload, Data([0x01, 0x02]))
    }

    func testGetArtifactsBySession() throws {
        for i in 0..<3 {
            try sm.insertArtifact(ArtifactRecord(
                artifactId: "art_\(i)", sessionId: "s1", subjectId: "usr_1",
                type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
                startMs: Int64(i * 1000), endMs: Int64((i + 1) * 1000), seq: i,
                createdAtMs: Int64(i * 1000), encAlg: "chacha20poly1305",
                payload: Data([0x00]), payloadSha256: "hash_\(i)"
            ))
        }

        let artifacts = try sm.getArtifactsBySession("s1", type: "hsi_window")
        XCTAssertEqual(artifacts.count, 3)
    }

    func testGetArtifactsByTimeRange() throws {
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "early", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 100, endMs: 200, createdAtMs: 100,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h1"
        ))
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "mid", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 500, endMs: 600, createdAtMs: 500,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h2"
        ))
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "late", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 1000, endMs: 1100, createdAtMs: 1000,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h3"
        ))

        let range = try sm.getArtifactsByTimeRange(400, 700, type: "hsi_window")
        XCTAssertEqual(range.count, 1)
        XCTAssertEqual(range.first?.artifactId, "mid")
    }

    // MARK: - Tombstones

    func testTombstoneExcludesArtifact() throws {
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "art_to_delete", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 0, endMs: 1, createdAtMs: 0,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h"
        ))

        XCTAssertFalse(try sm.isDeleted("art_to_delete"))
        try sm.insertTombstone(artifactId: "tombstone_1", targetArtifactId: "art_to_delete", reason: "user_request", deletedAtMs: 999)
        XCTAssertTrue(try sm.isDeleted("art_to_delete"))
    }

    // MARK: - Summary cache

    func testSummaryCacheInsertAndGet() throws {
        try sm.insertSummaryCache(
            sessionId: "s1",
            artifactId: "sum_1",
            summaryJson: "{\"total_windows\": 5}"
        )

        let json = try sm.getSummaryJson("s1")
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("total_windows"))
    }

    // MARK: - Wipe

    func testWipeAllClearsEverything() throws {
        try sm.insertSession(SessionRecord(
            sessionId: "s1", subjectId: "usr_1", mode: "personal",
            createdAtUtc: 1000, startUtc: 1000,
            appId: "app", appVersion: "1.0", deviceId: "d1", platform: "ios"
        ))
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "art_1", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 0, endMs: 1, createdAtMs: 0,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h"
        ))

        try sm.wipeAll()

        let sessions = try sm.listSessions()
        XCTAssertEqual(sessions.count, 0)

        let artifact = try sm.getArtifact("art_1")
        XCTAssertNil(artifact)
    }

    // MARK: - Delete session cascade

    func testDeleteSessionRemovesArtifacts() throws {
        try sm.insertSession(SessionRecord(
            sessionId: "s1", subjectId: "usr_1", mode: "personal",
            createdAtUtc: 1000, startUtc: 1000,
            appId: "app", appVersion: "1.0", deviceId: "d1", platform: "ios"
        ))
        try sm.insertArtifact(ArtifactRecord(
            artifactId: "art_1", sessionId: "s1", subjectId: "usr_1",
            type: "hsi_window", schemaName: "hsi_window", schemaVersion: "1",
            startMs: 0, endMs: 1, createdAtMs: 0,
            encAlg: "chacha20poly1305", payload: Data(), payloadSha256: "h"
        ))

        try sm.deleteSession("s1")

        let sessions = try sm.listSessions()
        XCTAssertEqual(sessions.count, 0)

        let artifacts = try sm.getArtifactsBySession("s1", type: "hsi_window")
        XCTAssertEqual(artifacts.count, 0)
    }
}
