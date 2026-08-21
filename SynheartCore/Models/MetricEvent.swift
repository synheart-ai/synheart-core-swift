import Foundation

/// An app-level metric event recorded during a session.
public struct MetricEvent {
    public let name: String
    public let timestampMs: Int64
    public let value: Any
    public let tags: [String: String]?

    public init(name: String, timestampMs: Int64, value: Any, tags: [String: String]? = nil) {
        self.name = name
        self.timestampMs = timestampMs
        self.value = value
        self.tags = tags
    }
}

/// Result of a storage usage query.
public struct StorageUsage {
    public let totalBytes: Int64
    public let bySessionBytes: [String: Int64]
    public let artifactCount: Int64
    public let sessionCount: Int64
    public let pendingSync: Int64

    public init(
        totalBytes: Int64,
        bySessionBytes: [String: Int64] = [:],
        artifactCount: Int64 = 0,
        sessionCount: Int64 = 0,
        pendingSync: Int64 = 0
    ) {
        self.totalBytes = totalBytes
        self.bySessionBytes = bySessionBytes
        self.artifactCount = artifactCount
        self.sessionCount = sessionCount
        self.pendingSync = pendingSync
    }

    init(runtimeMap map: [String: Any]) {
        func int64(_ key: String) -> Int64 {
            (map[key] as? NSNumber)?.int64Value ?? 0
        }

        let bySession = (map["by_session_bytes"] as? [String: Any])?.reduce(
            into: [String: Int64]()
        ) { result, entry in
            if let value = entry.value as? NSNumber {
                result[entry.key] = value.int64Value
            }
        } ?? [:]

        self.init(
            totalBytes: int64("total_bytes"),
            bySessionBytes: bySession,
            artifactCount: int64("artifact_count"),
            sessionCount: int64("session_count"),
            pendingSync: int64("pending_sync")
        )
    }
}

/// Result of an account deletion request.
public struct DeletionRequestResult {
    public let status: String
    public let message: String
    public let serverDeletionRequested: Bool
    public let localDataWiped: Bool

    public init(
        status: String,
        message: String,
        serverDeletionRequested: Bool = false,
        localDataWiped: Bool = false
    ) {
        self.status = status
        self.message = message
        self.serverDeletionRequested = serverDeletionRequested
        self.localDataWiped = localDataWiped
    }
}

/// Optional filter for listing sessions.
public struct SessionRange {
    public let startMs: Int64?
    public let endMs: Int64?
    public let mode: String?

    public init(startMs: Int64? = nil, endMs: Int64? = nil, mode: String? = nil) {
        self.startMs = startMs
        self.endMs = endMs
        self.mode = mode
    }
}

/// Optional filter for querying HSI windows.
public struct WindowRange {
    public let startMs: Int64?
    public let endMs: Int64?
    public let limit: Int?

    public init(startMs: Int64? = nil, endMs: Int64? = nil, limit: Int? = nil) {
        self.startMs = startMs
        self.endMs = endMs
        self.limit = limit
    }
}
