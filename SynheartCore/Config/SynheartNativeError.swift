import Foundation

/// Who can resolve a ``SynheartNativeError``.
///
/// If the integrating code can fix it without asking the person, the owner is
/// ``app`` even when the person sees the effect.
public enum NativeErrorOwner: String, Equatable, Sendable {
    /// The integrating code: call order, arguments, configuration, build.
    case app
    /// Only the person can act: sign in, grant consent, re-enter a code.
    case user
    /// Connectivity, the OS credential store, device capability. Usually wait.
    case environment
    /// The Synheart cloud refused or failed.
    case service
    /// A defect in the native runtime. Report it with ``SynheartNativeError/errorId``.
    case runtime
    /// The runtime sent no owner (older runtime) or one this SDK does not know.
    case unknown

    public static func parse(_ raw: String?) -> NativeErrorOwner {
        raw.flatMap(NativeErrorOwner.init(rawValue:)) ?? .unknown
    }
}

/// What to do about a ``SynheartNativeError``. One closed-set action per
/// failure; ``SynheartNativeError/recoveryCall`` names the native call that
/// performs it when there is one.
public enum NativeErrorRecovery: String, Equatable, Sendable {
    /// Repeat the same call, after ``SynheartNativeError/retryAfterMs`` if set.
    case retry
    /// Retry once the device is unlocked. Never wipe data for this.
    case waitForDeviceUnlock = "wait_for_device_unlock"
    /// Change the call: arguments, order, or which function.
    case fixCall = "fix_call"
    /// Change the configuration passed to `Synheart.initialize`.
    case fixConfiguration = "fix_configuration"
    /// Ask the person to re-enter what they typed.
    case reenterInput = "reenter_input"
    /// Re-authenticate the account.
    case signIn = "sign_in"
    /// Run device registration.
    case registerDevice = "register_device"
    /// Refresh the device attestation.
    case reattestDevice = "reattest_device"
    /// Sign out, then register again.
    case signOutThenRegister = "sign_out_then_register"
    /// Ask for the consent named in ``SynheartNativeError/reason``, then retry.
    case grantConsent = "grant_consent"
    /// Start pairing again on the other device.
    case generateNewPairingCode = "generate_new_pairing_code"
    /// Re-read sync readiness, then join or create a space.
    case rejoinSpace = "rejoin_space"
    /// Start a session, then retry.
    case startSessionFirst = "start_session_first"
    /// Stop the active session, then retry.
    case endSessionFirst = "end_session_first"
    /// The feature is compiled out of this runtime build.
    case useSupportedBuild = "use_supported_build"
    /// Report it, with ``SynheartNativeError/errorId`` and the diagnostic log.
    case reportBug = "report_bug"
    /// Nothing changes the outcome; show ``SynheartNativeError/message``.
    case none
    /// The runtime sent no recovery (older runtime) or one this SDK does not know.
    case unknown

    public static func parse(_ raw: String?) -> NativeErrorRecovery {
        guard let raw, raw != "unknown" else { return .unknown }
        return NativeErrorRecovery(rawValue: raw) ?? .unknown
    }
}

/// A structured failure reported by the native runtime.
///
/// Every runtime failure has this shape, whether it was read back after a call
/// that returned nil, `false` or a non-zero code, or arrived inside a failure
/// envelope. Branch on ``code`` and ``recoveryKind``; show ``message``; log
/// ``hint`` and ``errorId``. Internal detail (server bodies, paths, tokens)
/// never reaches here: it stays in the native diagnostic log, on the line
/// tagged with the same ``errorId``.
///
/// Every field beyond ``code``, ``message`` and ``retryable`` is optional in
/// both directions: an older runtime never sends it, and a newer SDK must not
/// assume it.
public struct SynheartNativeError: Error, @unchecked Sendable, LocalizedError, CustomStringConvertible {
    /// Stable machine-readable code, e.g. `CONSENT_REQUIRED`, `NETWORK`.
    /// Treat an unrecognised value as `UNKNOWN`.
    public let code: String

    /// End-user-safe message. Show it; never parse it.
    public let message: String

    /// Whether retrying the same call unchanged may succeed. Correct from
    /// runtime 0.20.0 on (the SDK's minimum).
    public let retryable: Bool

    /// Closed-set token narrowing the cause, or nil when there is none.
    ///
    /// On attestation and registration failures: `transient`, `timeout`,
    /// `quota`, `unsupported`, `misconfigured`, `server_transient`, `policy`,
    /// `unknown`. On `INVALID_ARGUMENT`: `null`, `not_utf8`, `blank`,
    /// `malformed`, `out_of_range`, `unrecognized`. On `CONSENT_REQUIRED`: the
    /// consent type to grant, e.g. `biosignals`.
    public let reason: String?

    /// Suggested backoff before retrying. Nil unless ``retryable``.
    public let retryAfterMs: Int?

    /// Diagnostics — `phase`, `http_status`, `server_code`, `argument`. Log it;
    /// branch on ``argument`` if you need the parameter, never on the shape.
    public let detail: [String: Any]?

    /// Raw `owner` token; see ``ownerKind``.
    public let owner: String?

    /// Raw `recovery` token; see ``recoveryKind``.
    public let recovery: String?

    /// The exact native function that performs ``recovery``, when one does,
    /// e.g. `synheart_core_grant_consent`. Agents should read this, not ``hint``.
    public let recoveryCall: String?

    /// One developer-facing sentence on the cause. Log it; it may be reworded
    /// in any runtime release, so never branch on it.
    public let hint: String?

    /// The native entry point that failed, e.g. `synheart_core_start_session`.
    public let op: String?

    /// Eight hex digits matching the native diagnostic log line for this
    /// failure. Put it in bug reports and "report a problem" UI.
    public let errorId: String?

    /// `runtime_version` and `abi`, present only when the runtime itself is at
    /// fault (``ownerKind`` is ``NativeErrorOwner/runtime``).
    public let report: [String: Any]?

    public init(
        code: String,
        message: String,
        retryable: Bool = false,
        reason: String? = nil,
        retryAfterMs: Int? = nil,
        detail: [String: Any]? = nil,
        owner: String? = nil,
        recovery: String? = nil,
        recoveryCall: String? = nil,
        hint: String? = nil,
        op: String? = nil,
        errorId: String? = nil,
        report: [String: Any]? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.reason = reason
        self.retryAfterMs = retryAfterMs
        self.detail = detail
        self.owner = owner
        self.recovery = recovery
        self.recoveryCall = recoveryCall
        self.hint = hint
        self.op = op
        self.errorId = errorId
        self.report = report
    }

    /// Parse a native error object. Missing or mistyped fields fall back to a
    /// safe shape, so a malformed payload never fails here.
    public init(map error: [String: Any]) {
        func str(_ key: String) -> String? {
            guard let v = error[key] as? String, !v.isEmpty else { return nil }
            return v
        }
        self.init(
            code: str("code") ?? "UNKNOWN",
            message: str("message") ?? "An unexpected error occurred.",
            retryable: error["retryable"] as? Bool ?? false,
            reason: str("reason"),
            // A JSON number may decode as Double across the FFI boundary.
            retryAfterMs: (error["retry_after_ms"] as? NSNumber)?.intValue,
            detail: error["detail"] as? [String: Any],
            owner: str("owner"),
            recovery: str("recovery"),
            recoveryCall: str("recovery_call"),
            hint: str("hint"),
            op: str("op"),
            errorId: str("error_id"),
            report: error["report"] as? [String: Any]
        )
    }

    /// Parse a native error JSON string; a malformed payload yields ``unknown``.
    public init(json: String) {
        if let data = json.data(using: .utf8),
           let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            self.init(map: map)
        } else {
            self = .unknown
        }
    }

    /// Fallback used when a failure is known but its payload is missing or
    /// malformed.
    public static let unknown = SynheartNativeError(
        code: "UNKNOWN",
        message: "An unexpected error occurred."
    )

    /// Who can resolve this failure.
    public var ownerKind: NativeErrorOwner { .parse(owner) }

    /// What to do about it.
    public var recoveryKind: NativeErrorRecovery { .parse(recovery) }

    /// On `INVALID_ARGUMENT`: the rejected parameter's name, e.g. `batch_json`.
    public var argument: String? { detail?["argument"] as? String }

    /// A defect in the runtime, not in the integrating code. Report it.
    public var isRuntimeBug: Bool { ownerKind == .runtime }

    /// The device can never attest (Simulator, unsupported hardware). Degrade
    /// to local-only and stop asking, including across relaunches.
    public var isUnsupported: Bool { reason == "unsupported" }

    /// The attestation setup is wrong; a developer has to fix it.
    public var isMisconfigured: Bool { reason == "misconfigured" }

    /// The server refused this device permanently.
    public var isPolicyRefusal: Bool { reason == "policy" }

    public var errorDescription: String? { message }

    public var description: String {
        // What lands in crash logs: enough to act on without the native log.
        var s = "SynheartNativeError(\(code)): \(message)"
        if let reason { s += " [reason: \(reason)]" }
        if let argument { s += " [argument: \(argument)]" }
        if let recovery { s += " [recovery: \(recovery)]" }
        if let recoveryCall { s += " [call: \(recoveryCall)]" }
        if let op { s += " [op: \(op)]" }
        if let errorId { s += " [error_id: \(errorId)]" }
        s += " (retryable: \(retryable)"
        if let retryAfterMs { s += ", retryAfterMs: \(retryAfterMs)" }
        return s + ")"
    }
}
