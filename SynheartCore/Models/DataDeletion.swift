import Foundation

public enum DataDeletionStatus: String, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
    case unknown

    public var isTerminal: Bool { self == .completed || self == .failed }

    static func decode(_ value: String?) -> DataDeletionStatus {
        value.flatMap(DataDeletionStatus.init(rawValue:)) ?? .unknown
    }
}

public struct DataDeletionRequest {
    public let requestId: String
    public let orgId: String
    public let tenantId: String
    public let userId: String
    public let status: DataDeletionStatus
    public let statusRaw: String
    public let dryRun: Bool
    public let reason: String?
    public let contact: String?
    public let result: [String: Any]?
    public let errorMessage: String?
    public let createdAt: Date
    public let startedAt: Date?
    public let completedAt: Date?
    public let failedAt: Date?

    public init(runtimeMap: [String: Any]) throws {
        guard let createdAt = Self.date(runtimeMap["created_at"]) else {
            throw SynheartCoreError.notConfigured("Data deletion response is missing created_at")
        }
        let rawStatus = runtimeMap["status"] as? String ?? "unknown"
        requestId = runtimeMap["request_id"] as? String ?? ""
        orgId = runtimeMap["org_id"] as? String ?? ""
        tenantId = runtimeMap["tenant_id"] as? String ?? ""
        userId = runtimeMap["user_id"] as? String ?? ""
        status = DataDeletionStatus.decode(rawStatus)
        statusRaw = rawStatus
        dryRun = runtimeMap["dry_run"] as? Bool ?? false
        reason = Self.nonEmpty(runtimeMap["reason"] as? String)
        contact = Self.nonEmpty(runtimeMap["contact"] as? String)
        result = runtimeMap["result"] as? [String: Any]
        errorMessage = Self.nonEmpty(runtimeMap["error_message"] as? String)
        self.createdAt = createdAt
        startedAt = Self.date(runtimeMap["started_at"])
        completedAt = Self.date(runtimeMap["completed_at"])
        failedAt = Self.date(runtimeMap["failed_at"])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func date(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

public struct DataDeletionList {
    public let requests: [DataDeletionRequest]
    public let total: Int

    public init(runtimeMap: [String: Any]) throws {
        let maps = runtimeMap["requests"] as? [[String: Any]] ?? []
        requests = try maps.map(DataDeletionRequest.init(runtimeMap:))
        total = (runtimeMap["total"] as? NSNumber)?.intValue ?? requests.count
    }
}

/// A cloud-side deletion lifecycle event delivered by the vendor stream.
public struct DataDeletionEvent {
    public let requestId: String
    public let userId: String
    public let appId: String
    public let orgId: String
    public let tenantId: String
    public let status: DataDeletionStatus
    public let statusRaw: String
    public let result: [String: Any]?
    public let errorMessage: String?
    public let emittedAt: Date

    public init?(envelope: [String: Any], appId: String, userId: String) {
        let payload: [String: Any]
        if let direct = envelope["payload"] as? [String: Any] {
            payload = direct
        } else if let raw = envelope["payload_json"] as? String,
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = decoded
        } else {
            return nil
        }
        guard let requestId = payload["request_id"] as? String, !requestId.isEmpty else { return nil }
        let rawStatus = payload["status"] as? String ?? "unknown"
        self.requestId = requestId
        self.userId = userId
        self.appId = appId
        orgId = payload["org_id"] as? String ?? ""
        tenantId = payload["tenant_id"] as? String ?? ""
        status = DataDeletionStatus.decode(rawStatus)
        statusRaw = rawStatus
        result = payload["result"] as? [String: Any]
        errorMessage = payload["error_message"] as? String
        let formatter = ISO8601DateFormatter()
        emittedAt = (envelope["created_at"] as? String).flatMap(formatter.date(from:)) ?? Date()
    }
}
