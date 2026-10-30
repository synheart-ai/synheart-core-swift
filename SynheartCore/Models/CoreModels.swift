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

/// Local Device Sync state, read from the runtime with no network call.
///
/// Runtime 0.39.0 and later report every field; on an older runtime the
/// fields it never sent stay `nil` (absent, not zero). The device roster is
/// not part of this: it lives on the server, so read it with
/// `Synheart.syncListDevices()`.
public struct SyncStatus {
    /// The sync engine is built.
    public let enabled: Bool

    /// The sync space this device is in, or `nil` when it is in none.
    public let syncSpaceId: String?

    /// Local artifacts waiting for the next push.
    public let pendingCount: Int?

    /// Unix ms of the last successful sync cycle since the engine was built.
    /// `nil` before the first success; it does not survive a restart.
    public let lastSuccessMs: Int64?

    /// The space key is unlocked, so pairing and pull can run.
    public let srkReady: Bool?

    /// The space is bound to a cloud account.
    public let accountOwned: Bool?

    /// Always `0`: the runtime no longer reports a device count (it never
    /// counted anything).
    @available(*, deprecated, message: "Always 0. Count the devices from Synheart.syncListDevices().")
    public var deviceCount: Int { 0 }

    /// This device is in a sync space.
    public var hasActiveSpace: Bool { syncSpaceId != nil }

    public init(
        enabled: Bool,
        syncSpaceId: String? = nil,
        pendingCount: Int? = nil,
        lastSuccessMs: Int64? = nil,
        srkReady: Bool? = nil,
        accountOwned: Bool? = nil
    ) {
        self.enabled = enabled
        self.syncSpaceId = syncSpaceId
        self.pendingCount = pendingCount
        self.lastSuccessMs = lastSuccessMs
        self.srkReady = srkReady
        self.accountOwned = accountOwned
    }

    @available(*, deprecated, message: "deviceCount is always 0; use init(enabled:syncSpaceId:pendingCount:lastSuccessMs:srkReady:accountOwned:).")
    public init(enabled: Bool, syncSpaceId: String? = nil, deviceCount: Int) {
        self.init(enabled: enabled, syncSpaceId: syncSpaceId)
    }

    /// Parses the runtime's `sync_status` payload. Missing or mistyped fields
    /// become `nil`; a missing `enabled` reads as `false`.
    init(runtimeMap map: [String: Any]) {
        let spaceId = map["sync_space_id"] as? String
        self.init(
            enabled: map["enabled"] as? Bool ?? false,
            syncSpaceId: spaceId?.isEmpty == false ? spaceId : nil,
            pendingCount: (map["pending_count"] as? NSNumber)?.intValue,
            lastSuccessMs: (map["last_success_ms"] as? NSNumber)?.int64Value,
            srkReady: map["srk_ready"] as? Bool,
            accountOwned: map["account_owned"] as? Bool
        )
    }
}

/// The server's verdict on a pairing token this device minted.
public enum SyncPairingState: String, Sendable {
    /// The code is valid and nobody has used it yet. Keep polling.
    case waiting
    /// Another device joined with the code. Stop polling.
    case joined
    /// The code expired unused. Stop polling and offer a new code.
    case expired
    /// The server sent a state this SDK does not know. Treat it as still
    /// pending: keep the code on screen, keep polling until `expiresAt`, and
    /// claim neither success nor failure.
    case unknown

    /// The state for the runtime's `status`; anything unrecognised is
    /// ``unknown``.
    public static func parse(_ raw: Any?) -> SyncPairingState {
        guard let raw = raw as? String, let state = SyncPairingState(rawValue: raw) else {
            return .unknown
        }
        return state
    }

    /// Polling can stop: the pairing reached a final state.
    public var isTerminal: Bool { self == .joined || self == .expired }
}

/// The device that joined with a pairing code.
public struct SyncPairedDevice: Equatable, Sendable {
    public let deviceId: String
    public let deviceName: String?

    public init(deviceId: String, deviceName: String? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}

/// Pairing status for a token from `Synheart.syncGeneratePairing()`.
///
/// Read it with `Synheart.syncPairingStatus(token:)` while the pairing code is
/// on screen, every 2–3 seconds, and stop when ``state`` is terminal
/// (``SyncPairingState/joined`` or ``SyncPairingState/expired``) or
/// ``expiresAt`` has passed.
public struct SyncPairingStatus: Equatable, Sendable {
    public let state: SyncPairingState

    /// The space the code invites into.
    public let syncSpaceId: String?

    /// The device that joined, once ``state`` is ``SyncPairingState/joined``.
    public let joinedDevice: SyncPairedDevice?

    /// When the other device joined.
    public let joinedAt: Date?

    /// When the code stops working. Bound the polling loop on it.
    public let expiresAt: Date?

    public init(
        state: SyncPairingState,
        syncSpaceId: String? = nil,
        joinedDevice: SyncPairedDevice? = nil,
        joinedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.state = state
        self.syncSpaceId = syncSpaceId
        self.joinedDevice = joinedDevice
        self.joinedAt = joinedAt
        self.expiresAt = expiresAt
    }

    /// The code is past its expiry, whatever the server last said.
    public func isExpired(at now: Date = Date()) -> Bool {
        if state == .expired { return true }
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Parses the runtime's `sync_pairing_status` payload.
    init(runtimeMap map: [String: Any]) {
        let spaceId = map["sync_space_id"] as? String
        var device: SyncPairedDevice?
        if let d = map["joined_device"] as? [String: Any], let id = d["device_id"] as? String {
            device = SyncPairedDevice(deviceId: id, deviceName: d["device_name"] as? String)
        }
        self.init(
            state: SyncPairingState.parse(map["status"]),
            syncSpaceId: spaceId?.isEmpty == false ? spaceId : nil,
            joinedDevice: device,
            joinedAt: Self.parseDate(map["joined_at"]),
            expiresAt: Self.parseDate(map["expires_at"])
        )
    }

    /// RFC 3339, with or without fractional seconds.
    static func parseDate(_ raw: Any?) -> Date? {
        guard let raw = raw as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
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
