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
}

/// Result of an account deletion request.
public struct DeletionRequestResult {
    public let status: String
    public let message: String
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
