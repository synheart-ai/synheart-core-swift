import Foundation

public enum NativeFailureReason: String, Sendable {
    case transient
    case timeout
    case quota
    case unsupported
    case misconfigured
    case serverTransient = "server_transient"
    case policy
    case unknown
}

public struct NativeOperationFailure: Equatable, Sendable {
    public let reason: NativeFailureReason
    public let message: String
    public let retryAfterMs: Int?
    public let detail: String?

    public var retryable: Bool {
        reason == .transient || reason == .timeout || reason == .quota || reason == .serverTransient
    }

    public init(
        reason: NativeFailureReason,
        message: String,
        retryAfterMs: Int? = nil,
        detail: String? = nil
    ) {
        self.reason = reason
        self.message = message
        self.retryAfterMs = retryAfterMs
        self.detail = detail
    }

    static func fromRuntimeMap(_ map: [String: Any], fallback: String) -> NativeOperationFailure? {
        let errorMap = map["error"] as? [String: Any]
        let errorString = map["error"] as? String
        guard errorMap != nil || errorString != nil || map["success"] as? Bool == false else {
            return nil
        }
        let rawReason = (errorMap?["reason"] ?? map["reason"]) as? String
        let reason = rawReason.flatMap(NativeFailureReason.init(rawValue:)) ?? .unknown
        let message = (errorMap?["message"] as? String)
            ?? (map["message"] as? String)
            ?? errorString
            ?? fallback
        let retryAfter = ((errorMap?["retry_after_ms"] ?? map["retry_after_ms"]) as? NSNumber)?.intValue
        let detailValue = errorMap?["detail"] ?? map["detail"]
        return NativeOperationFailure(
            reason: reason,
            message: message,
            retryAfterMs: retryAfter,
            detail: stringify(detailValue)
        )
    }

    private static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return String(data: data, encoding: .utf8)
        }
        return String(describing: value)
    }
}

public struct UploadFlushResult: Equatable, Sendable {
    public let success: Bool
    public let uploaded: Int
    public let failed: Int
    public let requeued: Int
    public let batchId: String?
    public let failure: NativeOperationFailure?

    public init(
        success: Bool,
        uploaded: Int = 0,
        failed: Int = 0,
        requeued: Int = 0,
        batchId: String? = nil,
        failure: NativeOperationFailure? = nil
    ) {
        self.success = success
        self.uploaded = uploaded
        self.failed = failed
        self.requeued = requeued
        self.batchId = batchId
        self.failure = failure
    }

    init(runtimeMap: [String: Any]) {
        let failure = NativeOperationFailure.fromRuntimeMap(runtimeMap, fallback: "Upload flush failed")
        self.init(
            success: failure == nil,
            uploaded: (runtimeMap["uploaded"] as? NSNumber)?.intValue ?? 0,
            failed: (runtimeMap["failed"] as? NSNumber)?.intValue ?? 0,
            requeued: (runtimeMap["requeued"] as? NSNumber)?.intValue ?? 0,
            batchId: runtimeMap["batch_id"] as? String,
            failure: failure
        )
    }
}

public enum CloudSyncState: String, Sendable {
    case localOnly
    case pending
    case syncing
    case synced
    case blocked
}

public struct UploadQueueStatus: Equatable, Sendable {
    public let state: CloudSyncState
    public let queueLength: Int
    public let lastUploadBatchId: String?
    public let lastUploadAt: Date?
    public let lastUploadAttemptAt: Date?
    public let lastFailure: NativeOperationFailure?

    public init(
        state: CloudSyncState,
        queueLength: Int,
        lastUploadBatchId: String? = nil,
        lastUploadAt: Date? = nil,
        lastUploadAttemptAt: Date? = nil,
        lastFailure: NativeOperationFailure? = nil
    ) {
        self.state = state
        self.queueLength = queueLength
        self.lastUploadBatchId = lastUploadBatchId
        self.lastUploadAt = lastUploadAt
        self.lastUploadAttemptAt = lastUploadAttemptAt
        self.lastFailure = lastFailure
    }
}

public struct DeviceAuthStatus: Equatable, Sendable {
    public let status: String
    public let deviceId: String?
    public let attestation: String

    public var isRegistered: Bool { status.lowercased() == "registered" }

    public init(status: String, deviceId: String? = nil, attestation: String = "unknown") {
        self.status = status
        self.deviceId = deviceId
        self.attestation = attestation
    }

    init(runtimeMap: [String: Any]) {
        self.init(
            status: runtimeMap["status"] as? String ?? "unknown",
            deviceId: runtimeMap["device_id"] as? String,
            attestation: runtimeMap["attestation"] as? String ?? "unknown"
        )
    }
}

public struct DeviceRegistrationResult: Equatable, Sendable {
    public let success: Bool
    public let status: DeviceAuthStatus
    public let failure: NativeOperationFailure?

    public init(success: Bool, status: DeviceAuthStatus, failure: NativeOperationFailure? = nil) {
        self.success = success
        self.status = status
        self.failure = failure
    }
}

