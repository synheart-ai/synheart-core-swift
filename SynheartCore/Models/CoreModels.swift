// SPDX-License-Identifier: Apache-2.0
//
// Public value types for the Swift Core SDK. These are the API-surface
// shapes the SDK returns; they are populated from the native runtime's
// JSON (sessions, sync) or thrown by the capability layer.

import Foundation

// MARK: - Sync

/// Outcome of a sync push/pull cycle, populated from the runtime result JSON.
public struct SyncResult {
    public let pushed: Int
    public let pulled: Int
    public let conflictsResolved: Int
    public let errors: [String]

    public init(
        pushed: Int = 0,
        pulled: Int = 0,
        conflictsResolved: Int = 0,
        errors: [String] = []
    ) {
        self.pushed = pushed
        self.pulled = pulled
        self.conflictsResolved = conflictsResolved
        self.errors = errors
    }

    init(runtimeMap map: [String: Any]) {
        self.init(
            pushed: (map["pushed"] as? NSNumber)?.intValue ?? 0,
            pulled: (map["pulled"] as? NSNumber)?.intValue ?? 0,
            conflictsResolved: (map["conflicts_resolved"] as? NSNumber)?.intValue ?? 0,
            errors: map["errors"] as? [String] ?? []
        )
    }
}

/// Whether background sync is currently enabled.
public struct SyncStatus {
    public let enabled: Bool
    public let syncSpaceId: String?
    public let deviceCount: Int

    public init(
        enabled: Bool,
        syncSpaceId: String? = nil,
        deviceCount: Int = 0
    ) {
        self.enabled = enabled
        self.syncSpaceId = syncSpaceId
        self.deviceCount = deviceCount
    }

    init(runtimeMap map: [String: Any]) {
        self.init(
            enabled: map["enabled"] as? Bool ?? false,
            syncSpaceId: map["sync_space_id"] as? String,
            deviceCount: (map["device_count"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - SessionRecord

/// Decoded snapshot of a stored session, created from the runtime's
/// `listSessions` JSON.
public struct SessionRecord {
    public let sessionId: String
    public let subjectId: String
    public let mode: String
    public let createdAtUtc: Int64
    public let startUtc: Int64
    public let endedAtUtc: Int64?
    public let state: String
    public let appId: String
    public let appVersion: String
    public let deviceId: String
    public let platform: String

    public init(
        sessionId: String,
        subjectId: String,
        mode: String,
        createdAtUtc: Int64,
        startUtc: Int64,
        endedAtUtc: Int64? = nil,
        state: String = "active",
        appId: String,
        appVersion: String,
        deviceId: String,
        platform: String
    ) {
        self.sessionId = sessionId
        self.subjectId = subjectId
        self.mode = mode
        self.createdAtUtc = createdAtUtc
        self.startUtc = startUtc
        self.endedAtUtc = endedAtUtc
        self.state = state
        self.appId = appId
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.platform = platform
    }

    /// Whether the native catalog still considers this session active.
    public var isActive: Bool { state == "active" }

    init?(runtimeMap map: [String: Any]) {
        guard let sessionId = map["session_id"] as? String,
              !sessionId.isEmpty else { return nil }

        func int64(_ keys: [String]) -> Int64? {
            for key in keys {
                if let number = map[key] as? NSNumber {
                    return number.int64Value
                }
            }
            return nil
        }

        self.init(
            sessionId: sessionId,
            subjectId: map["subject_id"] as? String ?? "",
            mode: map["mode"] as? String ?? "personal",
            createdAtUtc: int64(["created_at_utc", "created_at_ms"]) ?? 0,
            startUtc: int64(["started_at_ms", "start_utc"]) ?? 0,
            endedAtUtc: int64(["ended_at_ms", "end_utc"]),
            state: map["state"] as? String ?? "active",
            appId: map["app_id"] as? String ?? "",
            appVersion: map["app_version"] as? String ?? "",
            deviceId: map["device_id"] as? String ?? "",
            platform: map["platform"] as? String ?? "ios"
        )
    }
}

// MARK: - CapabilityException

/// Thrown by `CapabilityModule` when a requested feature is not allowed by
/// the loaded capability token.
public struct CapabilityException: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}
