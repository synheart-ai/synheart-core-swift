// SPDX-License-Identifier: Apache-2.0
//
// ─────────────────────────────────────────────────────────────────
// Compatibility stubs for the Swift Core SDK.
//
// Why this file exists:
//
//   The Swift Core SDK ships ahead of full runtime wiring on iOS.
//   Until the Swift surface reaches feature parity with the
//   Flutter and Kotlin SDKs (sync, session record, capability
//   error path, auth token, signed headers), the symbols below
//   are intentionally minimal placeholders annotated
//   `@available(*, deprecated)` so example code and downstream
//   targets keep compiling without pretending the features are
//   live.
//
//   These are NOT production APIs. Apps relying on these symbols
//   should treat them as scaffolding that will be replaced by
//   runtime-backed equivalents — the deprecation message on each
//   stub points at what's missing.
//
//   When the Swift SDK gains parity, this entire file is deleted.
//
// Canonical implementation lives in the Rust runtime:
//
//   - sync types & flows:
//       synheart-core-runtime/crates/core-runtime/src/sync/
//
// Do not extend the symbols here; extend them in the runtime and
// expose runtime-backed Swift wrappers in `CoreRuntime/`.
// ─────────────────────────────────────────────────────────────────
//
// Compatibility stubs for types referenced by Synheart.swift /
// SynheartCoreShim.swift / CapabilityModule.swift after the Rust
// runtime migration removed their original definitions.
//
// Each stub is the minimum shape required to make the package
// compile. Real implementations live in the runtime now and the
// SDK shells will switch to runtime-backed equivalents in a
// follow-on sit. This file exists so:
//
//   1. The Swift package builds (and tests run).
//   2. The new new CoreRuntime/ wrappers aren't
//      blocked by unrelated breakage.
//   3. Anyone reading a stub knows it's a placeholder, not a real
//      implementation, because of the @available(*, deprecated)
//      annotation.

import Foundation

// MARK: - SyncResult / SyncStatus

/// Outcome of a sync push/pull cycle. The runtime returns the
/// authoritative result; this struct exists for the public API
/// surface and is populated from the runtime JSON.
@available(*, deprecated, message: "Stub — runtime-backed sync not yet wired.")
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

@available(*, deprecated, message: "Stub — runtime-backed sync status not yet wired.")
public struct SyncStatus {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
}

// MARK: - SessionRecord

/// Decoded snapshot of a stored session. Created from the
/// runtime's `listSessions` JSON.
@available(*, deprecated, message: "Stub — runtime-backed session record not yet wired.")
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

/// Thrown by `CapabilityModule` when a requested feature is not
/// allowed by the loaded capability token.
@available(*, deprecated, message: "Stub — wire to real capability error type.")
public struct CapabilityException: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - AuthTokenStub

/// Placeholder for the auth token returned by
/// `ConsentModule.getCurrentToken`. Pre-migration the real type
/// lived alongside the in-process auth flow. The runtime owns
/// auth now; restore a real type in a follow-on sit.
@available(*, deprecated, message: "Stub — wire to runtime auth token.")
public struct AuthTokenStub {
    public let token: String
    public let isValid: Bool
    public init(token: String, isValid: Bool) {
        self.token = token
        self.isValid = isValid
    }
}

// MARK: - SynheartAuth (request signer placeholder)

/// Placeholder for the `SynheartAuth` request-signing facade. The
/// real type lives in `synheart-auth-swift`; this stub keeps the
/// Swift package compiling until that dependency is re-imported
/// in a follow-on sit.
@available(*, deprecated, message: "Stub — wire to real synheart-auth-swift facade.")
public final class SynheartAuth {
    public static let shared = SynheartAuth()
    private init() {}

    public func configure(baseUrl: String) {
        // no-op: real impl lives in synheart-auth-swift
    }

    /// Real signature lives in synheart-auth-swift; this stub
    /// matches the call shape used by `Synheart.swift` so the
    /// package compiles. The returned `SignedHeadersStub` exposes
    /// `.dictionary` for the same reason.
    public func signRequest(
        appId: String,
        method: String,
        path: String,
        bodyBytes: Data?
    ) throws -> SignedHeadersStub {
        return SignedHeadersStub(dictionary: [:])
    }
}

@available(*, deprecated, message: "Stub — wire to real synheart-auth-swift signed-headers type.")
public struct SignedHeadersStub {
    public let dictionary: [String: String]
    public init(dictionary: [String: String]) {
        self.dictionary = dictionary
    }
}
