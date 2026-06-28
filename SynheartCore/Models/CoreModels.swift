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
    public let errors: [String]

    public init(pushed: Int = 0, pulled: Int = 0, errors: [String] = []) {
        self.pushed = pushed
        self.pulled = pulled
        self.errors = errors
    }
}

/// Whether background sync is currently enabled.
public struct SyncStatus {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
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
        self.appId = appId
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.platform = platform
    }
}

// MARK: - CapabilityException

/// Thrown by `CapabilityModule` when a requested feature is not allowed by
/// the loaded capability token.
public struct CapabilityException: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}
