// SPDX-License-Identifier: Apache-2.0
//
// Typed Swift models for the snapshot-upload request / response pair.
// Mirrors the Flutter reference at `lib/src/modules/cloud/upload_models.dart`
// and the Kotlin sibling at `modules/cloud/UploadModels.kt`. snake_case
// wire keys for cross-language byte-equivalent JSON.

import Foundation

/// Per-batch metadata sent alongside snapshots — describes the SDK
/// version / platform / capability tier the snapshots were collected
/// under so the backend can apply the right schema validation.
public struct UploadMetadata: Equatable, Sendable {
    public let sdkVersion: String
    public let platform: String
    public let capabilityLevel: String
    public let orgId: String?

    public init(sdkVersion: String, platform: String,
                capabilityLevel: String, orgId: String? = nil) {
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.capabilityLevel = capabilityLevel
        self.orgId = orgId
    }

    public func toJson() -> [String: Any] {
        var out: [String: Any] = [
            "sdk_version": sdkVersion,
            "platform": platform,
            "capability_level": capabilityLevel,
        ]
        if let o = orgId { out["org_id"] = o }
        return out
    }

    public static func fromJson(_ json: [String: Any]) -> UploadMetadata {
        return UploadMetadata(
            sdkVersion: json["sdk_version"] as? String ?? "",
            platform: json["platform"] as? String ?? "",
            capabilityLevel: json["capability_level"] as? String ?? "",
            orgId: json["org_id"] as? String
        )
    }
}

/// One batch upload request.
///
/// `snapshots` is intentionally `[[String: Any]]` — snapshot shapes
/// evolve faster than the SDK and the backend validates against its
/// own schema. Hosts that need typed snapshots build them through the
/// artifact / HSI APIs and serialise to dictionaries for this call.
// Not `Sendable` because `snapshots: [[String: Any]]` contains
// arbitrary nested JSON the backend defines (Any is not Sendable).
// Match Flutter's `List<Map<String, dynamic>>` shape exactly.
public struct UploadRequest {
    public let userId: String
    public let metadata: UploadMetadata
    public let snapshots: [[String: Any]]

    public init(userId: String, metadata: UploadMetadata, snapshots: [[String: Any]]) {
        self.userId = userId
        self.metadata = metadata
        self.snapshots = snapshots
    }

    public func toJson() -> [String: Any] {
        return [
            "user_id": userId,
            "metadata": metadata.toJson(),
            "snapshots": snapshots,
        ]
    }

    public static func fromJson(_ json: [String: Any]) -> UploadRequest {
        return UploadRequest(
            userId: json["user_id"] as? String ?? "",
            metadata: UploadMetadata.fromJson(json["metadata"] as? [String: Any] ?? [:]),
            snapshots: (json["snapshots"] as? [[String: Any]]) ?? []
        )
    }
}

/// Successful upload response from the cloud connector.
public struct UploadResponse: Equatable, Sendable {
    public let success: Bool?
    public let batchId: String?
    public let snapshotIds: [String]?
    public let s3Keys: [String]?
    public let message: String?

    public init(success: Bool? = nil, batchId: String? = nil,
                snapshotIds: [String]? = nil, s3Keys: [String]? = nil,
                message: String? = nil) {
        self.success = success
        self.batchId = batchId
        self.snapshotIds = snapshotIds
        self.s3Keys = s3Keys
        self.message = message
    }

    public func toJson() -> [String: Any] {
        var out: [String: Any] = [:]
        if let s = success { out["success"] = s }
        if let b = batchId { out["batch_id"] = b }
        if let ids = snapshotIds { out["snapshot_ids"] = ids }
        if let keys = s3Keys { out["s3_keys"] = keys }
        if let m = message { out["message"] = m }
        return out
    }

    public static func fromJson(_ json: [String: Any]) -> UploadResponse {
        return UploadResponse(
            success: json["success"] as? Bool,
            batchId: json["batch_id"] as? String,
            snapshotIds: json["snapshot_ids"] as? [String],
            s3Keys: json["s3_keys"] as? [String],
            message: json["message"] as? String
        )
    }
}

/// Backend error envelope (HTTP 4xx / 5xx body).
public struct UploadErrorResponse: Equatable, Sendable {
    public let error: UploadErrorDetail?
    public let retryAfter: Int?

    public init(error: UploadErrorDetail? = nil, retryAfter: Int? = nil) {
        self.error = error
        self.retryAfter = retryAfter
    }

    public var errorCode: String { error?.code ?? "unknown" }
    public var errorMessage: String { error?.message ?? "Unknown error" }

    public func toJson() -> [String: Any] {
        var out: [String: Any] = [:]
        if let e = error { out["error"] = e.toJson() }
        if let r = retryAfter { out["retry_after"] = r }
        return out
    }

    public static func fromJson(_ json: [String: Any]) -> UploadErrorResponse {
        let detail: UploadErrorDetail?
        if let e = json["error"] as? [String: Any] {
            detail = UploadErrorDetail.fromJson(e)
        } else {
            detail = nil
        }
        return UploadErrorResponse(
            error: detail,
            retryAfter: json["retry_after"] as? Int
        )
    }
}

/// Discrete error payload inside `UploadErrorResponse.error`.
public struct UploadErrorDetail: Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: String?

    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public func toJson() -> [String: Any] {
        var out: [String: Any] = ["code": code, "message": message]
        if let d = details { out["details"] = d }
        return out
    }

    public static func fromJson(_ json: [String: Any]) -> UploadErrorDetail {
        return UploadErrorDetail(
            code: json["code"] as? String ?? "",
            message: json["message"] as? String ?? "",
            details: json["details"] as? String
        )
    }
}
