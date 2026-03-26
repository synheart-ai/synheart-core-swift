import Foundation
import SQLite3

/// Record representing a session row in the catalog.
public struct SessionRecord {
    public let sessionId: String
    public let subjectId: String
    public let mode: String
    public let createdAtUtc: Int64
    public let startUtc: Int64
    public let endUtc: Int64?
    public let appId: String
    public let appVersion: String
    public let deviceId: String
    public let platform: String
    public let state: String
    public let syncedState: String

    public init(
        sessionId: String, subjectId: String, mode: String,
        createdAtUtc: Int64, startUtc: Int64, endUtc: Int64? = nil,
        appId: String, appVersion: String, deviceId: String, platform: String,
        state: String = "active", syncedState: String = "disabled"
    ) {
        self.sessionId = sessionId
        self.subjectId = subjectId
        self.mode = mode
        self.createdAtUtc = createdAtUtc
        self.startUtc = startUtc
        self.endUtc = endUtc
        self.appId = appId
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.platform = platform
        self.state = state
        self.syncedState = syncedState
    }
}

/// Record representing an artifact row in the catalog.
public struct ArtifactRecord {
    public let artifactId: String
    public let sessionId: String?
    public let subjectId: String
    public let type: String
    public let schemaName: String
    public let schemaVersion: String
    public let startMs: Int64
    public let endMs: Int64
    public let seq: Int?
    public let createdAtMs: Int64
    public let encAlg: String
    public let payload: Data
    public let payloadSha256: String
    public let syncState: String

    public init(
        artifactId: String, sessionId: String? = nil, subjectId: String,
        type: String, schemaName: String, schemaVersion: String,
        startMs: Int64, endMs: Int64, seq: Int? = nil, createdAtMs: Int64,
        encAlg: String, payload: Data, payloadSha256: String,
        syncState: String = "pending"
    ) {
        self.artifactId = artifactId
        self.sessionId = sessionId
        self.subjectId = subjectId
        self.type = type
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.startMs = startMs
        self.endMs = endMs
        self.seq = seq
        self.createdAtMs = createdAtMs
        self.encAlg = encAlg
        self.payload = payload
        self.payloadSha256 = payloadSha256
        self.syncState = syncState
    }
}

/// SQLite-based artifact and session storage.
///
/// See RFC-CORE-0004 for the full storage specification.
public final class StorageManager {
    private var db: OpaquePointer?
    private let basePath: String
    private let dbPathOverride: String?

    public init(basePath: String, dbPathOverride: String? = nil) {
        self.basePath = basePath
        self.dbPathOverride = dbPathOverride
    }

    public var isOpen: Bool { db != nil }

    public func open() throws {
        let dbPath: String
        if let override = dbPathOverride {
            dbPath = override
        } else {
            let dir = (basePath as NSString).appendingPathComponent("synheart/v1")
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            dbPath = (dir as NSString).appendingPathComponent("catalog.sqlite")
        }

        var dbPtr: OpaquePointer?
        let openResult = sqlite3_open(dbPath, &dbPtr)
        if openResult != SQLITE_OK {
            // First attempt failed — close handle, delete corrupt file, retry once
            if let ptr = dbPtr { sqlite3_close(ptr) }
            dbPtr = nil
            SynheartLogger.log("[StorageManager] sqlite3_open failed (code \(openResult)). Deleting corrupt DB and retrying...")
            try? FileManager.default.removeItem(atPath: dbPath)

            guard sqlite3_open(dbPath, &dbPtr) == SQLITE_OK else {
                throw NSError(domain: "StorageManager", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to open database after recovery attempt"])
            }
        }
        db = dbPtr

        do {
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA foreign_keys=ON")
            try createTables()
        } catch {
            // PRAGMAs or table creation failed — DB may be corrupt despite opening
            SynheartLogger.log("[StorageManager] Post-open setup failed: \(error). Deleting DB and retrying...")
            if let ptr = db { sqlite3_close(ptr) }
            db = nil
            try? FileManager.default.removeItem(atPath: dbPath)

            var retryPtr: OpaquePointer?
            guard sqlite3_open(dbPath, &retryPtr) == SQLITE_OK else {
                throw NSError(domain: "StorageManager", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to open database after recovery attempt"])
            }
            db = retryPtr
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA foreign_keys=ON")
            try createTables()
        }
    }

    public func close() {
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
    }

    // MARK: - Schema

    private func createTables() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                subject_id TEXT NOT NULL,
                mode TEXT NOT NULL,
                created_at_utc INTEGER NOT NULL,
                start_utc INTEGER NOT NULL,
                end_utc INTEGER NULL,
                app_id TEXT NOT NULL,
                app_version TEXT NOT NULL,
                device_id TEXT NOT NULL,
                platform TEXT NOT NULL,
                state TEXT NOT NULL DEFAULT 'active',
                synced_state TEXT NOT NULL DEFAULT 'disabled'
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_utc)")

        try exec("""
            CREATE TABLE IF NOT EXISTS artifacts (
                artifact_id TEXT PRIMARY KEY,
                session_id TEXT,
                subject_id TEXT NOT NULL,
                type TEXT NOT NULL,
                schema_name TEXT NOT NULL,
                schema_version TEXT NOT NULL,
                start_ms INTEGER NOT NULL,
                end_ms INTEGER NOT NULL,
                seq INTEGER,
                created_at_ms INTEGER NOT NULL,
                enc_alg TEXT NOT NULL,
                payload BLOB NOT NULL,
                payload_sha256 TEXT NOT NULL,
                sync_state TEXT NOT NULL DEFAULT 'pending',
                FOREIGN KEY(session_id) REFERENCES sessions(session_id)
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_artifacts_session ON artifacts(session_id)")
        try exec("CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(type)")
        try exec("CREATE INDEX IF NOT EXISTS idx_artifacts_time ON artifacts(start_ms, end_ms)")

        try exec("""
            CREATE TABLE IF NOT EXISTS summaries (
                session_id TEXT PRIMARY KEY,
                artifact_id TEXT NOT NULL,
                summary_json TEXT NOT NULL,
                computed_at_utc INTEGER NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id),
                FOREIGN KEY(artifact_id) REFERENCES artifacts(artifact_id)
            )
        """)

        try exec("""
            CREATE TABLE IF NOT EXISTS tombstones (
                artifact_id TEXT PRIMARY KEY,
                target_artifact_id TEXT NOT NULL,
                reason TEXT NOT NULL,
                deleted_at_ms INTEGER NOT NULL
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_tombstones_target ON tombstones(target_artifact_id)")

        try exec("""
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                name TEXT NOT NULL,
                timestamp_ms INTEGER NOT NULL,
                value TEXT NOT NULL,
                tags TEXT,
                FOREIGN KEY(session_id) REFERENCES sessions(session_id)
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_metrics_session ON metrics(session_id)")

        try exec("""
            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)

        try exec("""
            CREATE TABLE IF NOT EXISTS wearable_events (
                event_id TEXT PRIMARY KEY,
                subject_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                event_class TEXT NOT NULL,
                provider TEXT NOT NULL,
                provider_record_id TEXT,
                observed_at TEXT NOT NULL,
                ingested_at TEXT NOT NULL,
                effective_start TEXT,
                effective_end TEXT,
                payload BLOB NOT NULL,
                provenance TEXT,
                confidence REAL NOT NULL,
                source_fidelity TEXT NOT NULL,
                schema_version INTEGER NOT NULL DEFAULT 1
            )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_we_type_observed ON wearable_events(event_type, observed_at)")
        try exec("CREATE INDEX IF NOT EXISTS idx_we_subject ON wearable_events(subject_id)")
    }

    // MARK: - Sessions

    public func insertSession(_ session: SessionRecord) throws {
        let sql = """
            INSERT OR IGNORE INTO sessions
            (session_id, subject_id, mode, created_at_utc, start_utc, end_utc,
             app_id, app_version, device_id, platform, state, synced_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (session.sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session.subjectId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (session.mode as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, session.createdAtUtc)
        sqlite3_bind_int64(stmt, 5, session.startUtc)
        if let endUtc = session.endUtc {
            sqlite3_bind_int64(stmt, 6, endUtc)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_text(stmt, 7, (session.appId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (session.appVersion as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (session.deviceId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 10, (session.platform as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 11, (session.state as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 12, (session.syncedState as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func updateSession(_ sessionId: String, state: String? = nil, endUtc: Int64? = nil) throws {
        var sets: [String] = []
        if state != nil { sets.append("state = ?") }
        if endUtc != nil { sets.append("end_utc = ?") }
        guard !sets.isEmpty else { return }

        let sql = "UPDATE sessions SET \(sets.joined(separator: ", ")) WHERE session_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let s = state { sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, nil); idx += 1 }
        if let e = endUtc { sqlite3_bind_int64(stmt, idx, e); idx += 1 }
        sqlite3_bind_text(stmt, idx, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func listSessions(startMs: Int64? = nil, endMs: Int64? = nil, mode: SynheartMode? = nil) throws -> [SessionRecord] {
        var wheres: [String] = []
        if startMs != nil { wheres.append("start_utc >= ?") }
        if endMs != nil { wheres.append("start_utc <= ?") }
        if mode != nil { wheres.append("mode = ?") }
        wheres.append("state != 'deleted'")

        let sql = "SELECT * FROM sessions WHERE \(wheres.joined(separator: " AND ")) ORDER BY start_utc DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let s = startMs { sqlite3_bind_int64(stmt, idx, s); idx += 1 }
        if let e = endMs { sqlite3_bind_int64(stmt, idx, e); idx += 1 }
        if let m = mode { sqlite3_bind_text(stmt, idx, (m.rawValue as NSString).utf8String, -1, nil); idx += 1 }

        var results: [SessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(sessionFromRow(stmt))
        }
        return results
    }

    // MARK: - Artifacts

    public func insertArtifact(_ artifact: ArtifactRecord) throws {
        let sql = """
            INSERT OR IGNORE INTO artifacts
            (artifact_id, session_id, subject_id, type, schema_name, schema_version,
             start_ms, end_ms, seq, created_at_ms, enc_alg, payload, payload_sha256, sync_state)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (artifact.artifactId as NSString).utf8String, -1, nil)
        if let sid = artifact.sessionId {
            sqlite3_bind_text(stmt, 2, (sid as NSString).utf8String, -1, nil)
        } else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, (artifact.subjectId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (artifact.type as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (artifact.schemaName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (artifact.schemaVersion as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 7, artifact.startMs)
        sqlite3_bind_int64(stmt, 8, artifact.endMs)
        if let seq = artifact.seq { sqlite3_bind_int(stmt, 9, Int32(seq)) }
        else { sqlite3_bind_null(stmt, 9) }
        sqlite3_bind_int64(stmt, 10, artifact.createdAtMs)
        sqlite3_bind_text(stmt, 11, (artifact.encAlg as NSString).utf8String, -1, nil)
        artifact.payload.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 12, ptr.baseAddress, Int32(artifact.payload.count), nil)
        }
        sqlite3_bind_text(stmt, 13, (artifact.payloadSha256 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 14, (artifact.syncState as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func getArtifact(artifactId artifactId_: String) throws -> ArtifactRecord? {
        try getArtifact(artifactId_)
    }

    public func getArtifact(_ artifactId: String) throws -> ArtifactRecord? {
        let sql = "SELECT * FROM artifacts WHERE artifact_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (artifactId as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return artifactFromRow(stmt)
    }

    public func getArtifactsBySession(_ sessionId: String, type: String? = nil) throws -> [ArtifactRecord] {
        var wheres = ["session_id = ?"]
        if type != nil { wheres.append("type = ?") }
        wheres.append("artifact_id NOT IN (SELECT target_artifact_id FROM tombstones)")

        let sql = "SELECT * FROM artifacts WHERE \(wheres.joined(separator: " AND ")) ORDER BY start_ms ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        sqlite3_bind_text(stmt, idx, (sessionId as NSString).utf8String, -1, nil); idx += 1
        if let t = type { sqlite3_bind_text(stmt, idx, (t as NSString).utf8String, -1, nil); idx += 1 }

        var results: [ArtifactRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(artifactFromRow(stmt))
        }
        return results
    }

    public func getArtifactsByTimeRange(_ startMs: Int64, _ endMs: Int64, type: String? = nil) throws -> [ArtifactRecord] {
        var wheres = ["start_ms >= ?", "end_ms <= ?"]
        if type != nil { wheres.append("type = ?") }
        wheres.append("artifact_id NOT IN (SELECT target_artifact_id FROM tombstones)")

        let sql = "SELECT * FROM artifacts WHERE \(wheres.joined(separator: " AND ")) ORDER BY start_ms ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        sqlite3_bind_int64(stmt, idx, startMs); idx += 1
        sqlite3_bind_int64(stmt, idx, endMs); idx += 1
        if let t = type { sqlite3_bind_text(stmt, idx, (t as NSString).utf8String, -1, nil); idx += 1 }

        var results: [ArtifactRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(artifactFromRow(stmt))
        }
        return results
    }

    // MARK: - Tombstones

    public func insertTombstone(artifactId: String, targetArtifactId: String, reason: String, deletedAtMs: Int64) throws {
        let sql = "INSERT OR IGNORE INTO tombstones (artifact_id, target_artifact_id, reason, deleted_at_ms) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (artifactId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (targetArtifactId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (reason as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, deletedAtMs)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func isDeleted(_ artifactId: String) throws -> Bool {
        let sql = "SELECT 1 FROM tombstones WHERE target_artifact_id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (artifactId as NSString).utf8String, -1, nil)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - Summaries

    public func insertSummaryCache(sessionId: String, artifactId: String, summaryJson: String) throws {
        let sql = "INSERT OR REPLACE INTO summaries (session_id, artifact_id, summary_json, computed_at_utc) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (artifactId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (summaryJson as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func getSummaryJson(_ sessionId: String) throws -> String? {
        let sql = "SELECT summary_json FROM summaries WHERE session_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    // MARK: - Metrics

    public func insertMetric(sessionId: String, event: MetricEvent) throws {
        let valueJson: String
        if let num = event.value as? NSNumber {
            valueJson = "\(num)"
        } else if let str = event.value as? String {
            let escaped = str.replacingOccurrences(of: "\"", with: "\\\"")
            valueJson = "\"\(escaped)\""
        } else if let bool = event.value as? Bool {
            valueJson = bool ? "true" : "false"
        } else {
            valueJson = "null"
        }

        let sql = "INSERT INTO metrics (session_id, name, timestamp_ms, value, tags) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (event.name as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, event.timestampMs)
        sqlite3_bind_text(stmt, 4, (valueJson as NSString).utf8String, -1, nil)
        if let tags = event.tags, let tagsData = try? JSONSerialization.data(withJSONObject: tags),
           let tagsStr = String(data: tagsData, encoding: .utf8) {
            sqlite3_bind_text(stmt, 5, (tagsStr as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func aggregateMetrics(sessionId: String) throws -> [[String: Any]] {
        let sql = "SELECT name, COUNT(*) as cnt, AVG(CAST(value AS REAL)) as avg_val FROM metrics WHERE session_id = ? GROUP BY name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append([
                "name": String(cString: sqlite3_column_text(stmt, 0)),
                "count": Int(sqlite3_column_int(stmt, 1)),
                "mean": sqlite3_column_double(stmt, 2)
            ])
        }
        return results
    }

    // MARK: - Storage Usage

    public func getStorageUsage() throws -> StorageUsage {
        let sql = "SELECT session_id, SUM(LENGTH(payload)) as bytes FROM artifacts GROUP BY session_id"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        var total: Int64 = 0
        var bySession: [String: Int64] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sid = sqlite3_column_type(stmt, 0) == SQLITE_NULL ? "~" : String(cString: sqlite3_column_text(stmt, 0))
            let bytes = sqlite3_column_int64(stmt, 1)
            bySession[sid] = bytes
            total += bytes
        }
        return StorageUsage(totalBytes: total, bySessionBytes: bySession)
    }

    // MARK: - Retention

    public func enforceRetention(cutoffMs: Int64) throws -> Int {
        let cutoffUtc = cutoffMs / 1000
        let sql = "SELECT session_id FROM sessions WHERE start_utc < ? AND state != 'deleted'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, cutoffUtc)

        var sessionIds: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sessionIds.append(String(cString: sqlite3_column_text(stmt, 0)))
        }

        for sid in sessionIds {
            try deleteSession(sid, createTombstones: true)
        }
        return sessionIds.count
    }

    // MARK: - Deletion

    public func deleteSession(_ sessionId: String, createTombstones: Bool = false) throws {
        if createTombstones {
            let sql = "SELECT artifact_id FROM artifacts WHERE session_id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let aid = String(cString: sqlite3_column_text(stmt, 0))
                let tombId = "tombstone_\(aid)"
                try insertTombstone(artifactId: tombId, targetArtifactId: aid,
                                    reason: "session_deleted", deletedAtMs: nowMs)
                // Insert tombstone as a syncable artifact so it gets pushed during sync
                let payloadStr = "{\"target\":\"\(aid)\",\"reason\":\"session_deleted\"}"
                let payloadData = payloadStr.data(using: .utf8) ?? Data()
                try insertArtifact(ArtifactRecord(
                    artifactId: tombId,
                    sessionId: sessionId,
                    subjectId: "", // will be overwritten below
                    type: "tombstone",
                    schemaName: "tombstone",
                    schemaVersion: "1.0",
                    startMs: nowMs,
                    endMs: nowMs,
                    createdAtMs: nowMs,
                    encAlg: "none",
                    payload: payloadData,
                    payloadSha256: "",
                    syncState: "pending"
                ))
            }
        }

        try exec("DELETE FROM metrics WHERE session_id = '\(sessionId)'")
        try exec("DELETE FROM summaries WHERE session_id = '\(sessionId)'")
        try exec("DELETE FROM artifacts WHERE session_id = '\(sessionId)' AND type != 'tombstone'")
        try exec("UPDATE sessions SET state = 'deleted' WHERE session_id = '\(sessionId)'")
    }

    // MARK: - Sync State

    public func setSyncState(key: String, value: String) throws {
        let sql = "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func getSyncStateValue(key: String) throws -> String? {
        let sql = "SELECT value FROM sync_state WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    public func markSynced(artifactId: String) throws {
        try exec("UPDATE artifacts SET sync_state = 'synced' WHERE artifact_id = '\(artifactId)'")
    }

    public func getUnsyncedArtifacts(limit: Int) throws -> [ArtifactRecord] {
        let sql = "SELECT * FROM artifacts WHERE sync_state = 'pending' ORDER BY created_at_ms ASC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [ArtifactRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(artifactFromRow(stmt))
        }
        return results
    }

    public func getUnsyncedCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM artifacts WHERE sync_state = 'pending'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func isDeleted(artifactId: String) throws -> Bool {
        try isDeleted(artifactId)
    }

    /// Find an existing artifact_id that matches the given conflict key (session_id, type, start_ms, schema_version).
    /// Returns the artifact_id if found, nil otherwise.
    public func findConflictingArtifactId(sessionId: String, type: String, startMs: Int64, schemaVersion: String) throws -> String? {
        let sql = "SELECT artifact_id FROM artifacts WHERE session_id = ? AND type = ? AND start_ms = ? AND schema_version = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (type as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, startMs)
        sqlite3_bind_text(stmt, 4, (schemaVersion as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    // MARK: - Wearable Events

    public func insertWearableEvent(_ record: [String: Any]) throws {
        let sql = """
            INSERT OR IGNORE INTO wearable_events
            (event_id, subject_id, event_type, event_class, provider, provider_record_id,
             observed_at, ingested_at, effective_start, effective_end, payload,
             provenance, confidence, source_fidelity, schema_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ((record["event_id"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, ((record["subject_id"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ((record["event_type"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, ((record["event_class"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, ((record["provider"] as? String ?? "") as NSString).utf8String, -1, nil)

        if let rid = record["provider_record_id"] as? String {
            sqlite3_bind_text(stmt, 6, (rid as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        sqlite3_bind_text(stmt, 7, ((record["observed_at"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, ((record["ingested_at"] as? String ?? "") as NSString).utf8String, -1, nil)

        if let es = record["effective_start"] as? String {
            sqlite3_bind_text(stmt, 9, (es as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        if let ee = record["effective_end"] as? String {
            sqlite3_bind_text(stmt, 10, (ee as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        if let payloadStr = record["payload"] as? String,
           let payloadData = payloadStr.data(using: .utf8) {
            payloadData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 11, ptr.baseAddress, Int32(payloadData.count), nil)
            }
        } else {
            let empty = Data("{}".utf8)
            empty.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 11, ptr.baseAddress, Int32(empty.count), nil)
            }
        }

        if let prov = record["provenance"] as? String {
            sqlite3_bind_text(stmt, 12, (prov as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 12)
        }

        sqlite3_bind_double(stmt, 13, record["confidence"] as? Double ?? 0.0)
        sqlite3_bind_text(stmt, 14, ((record["source_fidelity"] as? String ?? "provider_summary") as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 15, Int32(record["schema_version"] as? Int ?? 1))

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    public func queryWearableEvents(eventType: String, startDate: String, endDate: String) throws -> [[String: Any]] {
        let sql = "SELECT * FROM wearable_events WHERE event_type = ? AND observed_at >= ? AND observed_at <= ? ORDER BY observed_at ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (eventType as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (startDate as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (endDate as NSString).utf8String, -1, nil)

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(wearableEventFromRow(stmt))
        }
        return results
    }

    public func wearableEventCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM wearable_events"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { throw sqliteError() }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func wipeAll() throws {
        try exec("DELETE FROM metrics")
        try exec("DELETE FROM tombstones")
        try exec("DELETE FROM summaries")
        try exec("DELETE FROM artifacts")
        try exec("DELETE FROM sessions")
        try exec("DELETE FROM sync_state")
        try exec("DELETE FROM wearable_events")
    }

    // MARK: - Helpers

    private var database: OpaquePointer {
        guard let db = db else { fatalError("StorageManager is not open") }
        return db
    }

    private func exec(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMsg) == SQLITE_OK else {
            let msg = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw NSError(domain: "StorageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func sqliteError() -> NSError {
        let msg = String(cString: sqlite3_errmsg(database))
        return NSError(domain: "StorageManager", code: Int(sqlite3_errcode(database)), userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private func sessionFromRow(_ stmt: OpaquePointer?) -> SessionRecord {
        SessionRecord(
            sessionId: String(cString: sqlite3_column_text(stmt, 0)),
            subjectId: String(cString: sqlite3_column_text(stmt, 1)),
            mode: String(cString: sqlite3_column_text(stmt, 2)),
            createdAtUtc: sqlite3_column_int64(stmt, 3),
            startUtc: sqlite3_column_int64(stmt, 4),
            endUtc: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
            appId: String(cString: sqlite3_column_text(stmt, 6)),
            appVersion: String(cString: sqlite3_column_text(stmt, 7)),
            deviceId: String(cString: sqlite3_column_text(stmt, 8)),
            platform: String(cString: sqlite3_column_text(stmt, 9)),
            state: String(cString: sqlite3_column_text(stmt, 10)),
            syncedState: String(cString: sqlite3_column_text(stmt, 11))
        )
    }

    private func artifactFromRow(_ stmt: OpaquePointer?) -> ArtifactRecord {
        let blobPtr = sqlite3_column_blob(stmt, 11)
        let blobLen = sqlite3_column_bytes(stmt, 11)
        let payload = blobPtr.map { Data(bytes: $0, count: Int(blobLen)) } ?? Data()

        return ArtifactRecord(
            artifactId: String(cString: sqlite3_column_text(stmt, 0)),
            sessionId: sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 1)),
            subjectId: String(cString: sqlite3_column_text(stmt, 2)),
            type: String(cString: sqlite3_column_text(stmt, 3)),
            schemaName: String(cString: sqlite3_column_text(stmt, 4)),
            schemaVersion: String(cString: sqlite3_column_text(stmt, 5)),
            startMs: sqlite3_column_int64(stmt, 6),
            endMs: sqlite3_column_int64(stmt, 7),
            seq: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 8)),
            createdAtMs: sqlite3_column_int64(stmt, 9),
            encAlg: String(cString: sqlite3_column_text(stmt, 10)),
            payload: payload,
            payloadSha256: String(cString: sqlite3_column_text(stmt, 12)),
            syncState: sqlite3_column_type(stmt, 13) == SQLITE_NULL ? "pending" : String(cString: sqlite3_column_text(stmt, 13))
        )
    }

    private func wearableEventFromRow(_ stmt: OpaquePointer?) -> [String: Any] {
        var row: [String: Any] = [
            "event_id": String(cString: sqlite3_column_text(stmt, 0)),
            "subject_id": String(cString: sqlite3_column_text(stmt, 1)),
            "event_type": String(cString: sqlite3_column_text(stmt, 2)),
            "event_class": String(cString: sqlite3_column_text(stmt, 3)),
            "provider": String(cString: sqlite3_column_text(stmt, 4)),
            "observed_at": String(cString: sqlite3_column_text(stmt, 6)),
            "ingested_at": String(cString: sqlite3_column_text(stmt, 7)),
            "confidence": sqlite3_column_double(stmt, 12),
            "source_fidelity": String(cString: sqlite3_column_text(stmt, 13)),
            "schema_version": Int(sqlite3_column_int(stmt, 14)),
        ]

        if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
            row["provider_record_id"] = String(cString: sqlite3_column_text(stmt, 5))
        }
        if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
            row["effective_start"] = String(cString: sqlite3_column_text(stmt, 8))
        }
        if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
            row["effective_end"] = String(cString: sqlite3_column_text(stmt, 9))
        }

        let blobPtr = sqlite3_column_blob(stmt, 10)
        let blobLen = sqlite3_column_bytes(stmt, 10)
        if let ptr = blobPtr, blobLen > 0 {
            let data = Data(bytes: ptr, count: Int(blobLen))
            if let str = String(data: data, encoding: .utf8) {
                row["payload"] = str
            }
        }

        if sqlite3_column_type(stmt, 11) != SQLITE_NULL {
            row["provenance"] = String(cString: sqlite3_column_text(stmt, 11))
        }

        return row
    }

    deinit {
        close()
    }
}
