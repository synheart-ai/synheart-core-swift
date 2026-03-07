import Foundation

/// Wire format for E2EE artifact sync (RFC-CORE-0005 §4).
public struct ArtifactEnvelope {
    public let envelopeVersion: String
    public let artifactId: String
    public let subjectId: String
    public let sessionId: String?
    public let type: String
    public let startMs: Int64
    public let endMs: Int64
    public let seq: Int?
    public let schemaName: String
    public let schemaVersion: String
    public let cryptoAlg: String
    public let nonceB64: String
    public let compression: String
    public let payloadSha256: String
    public let ciphertextB64: String

    public init(
        envelopeVersion: String = "1",
        artifactId: String,
        subjectId: String,
        sessionId: String? = nil,
        type: String,
        startMs: Int64,
        endMs: Int64,
        seq: Int? = nil,
        schemaName: String,
        schemaVersion: String,
        cryptoAlg: String = "CHACHA20POLY1305",
        nonceB64: String,
        compression: String = "none",
        payloadSha256: String,
        ciphertextB64: String
    ) {
        self.envelopeVersion = envelopeVersion
        self.artifactId = artifactId
        self.subjectId = subjectId
        self.sessionId = sessionId
        self.type = type
        self.startMs = startMs
        self.endMs = endMs
        self.seq = seq
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.cryptoAlg = cryptoAlg
        self.nonceB64 = nonceB64
        self.compression = compression
        self.payloadSha256 = payloadSha256
        self.ciphertextB64 = ciphertextB64
    }

    public func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "envelope_version": envelopeVersion,
            "artifact_id": artifactId,
            "subject_id": subjectId,
            "type": type,
            "time_range": ["start_ms": startMs, "end_ms": endMs],
            "schema": ["name": schemaName, "version": schemaVersion],
            "crypto": ["alg": cryptoAlg, "nonce_b64": nonceB64],
            "compression": compression,
            "payload_sha256": payloadSha256,
            "ciphertext_b64": ciphertextB64,
        ]
        if let sid = sessionId { json["session_id"] = sid }
        if let s = seq { json["seq"] = s }
        return json
    }

    public static func fromJson(_ json: [String: Any]) -> ArtifactEnvelope {
        let timeRange = json["time_range"] as! [String: Any]
        let schema = json["schema"] as! [String: Any]
        let crypto = json["crypto"] as! [String: Any]

        return ArtifactEnvelope(
            envelopeVersion: json["envelope_version"] as? String ?? "1",
            artifactId: json["artifact_id"] as! String,
            subjectId: json["subject_id"] as! String,
            sessionId: json["session_id"] as? String,
            type: json["type"] as! String,
            startMs: (timeRange["start_ms"] as! NSNumber).int64Value,
            endMs: (timeRange["end_ms"] as! NSNumber).int64Value,
            seq: json["seq"] as? Int,
            schemaName: schema["name"] as! String,
            schemaVersion: schema["version"] as! String,
            cryptoAlg: crypto["alg"] as? String ?? "CHACHA20POLY1305",
            nonceB64: crypto["nonce_b64"] as! String,
            compression: json["compression"] as? String ?? "none",
            payloadSha256: json["payload_sha256"] as! String,
            ciphertextB64: json["ciphertext_b64"] as! String
        )
    }
}

/// Result of a sync operation.
public struct SyncResult {
    public let pushed: Int
    public let pulled: Int
    public let conflictsResolved: Int
    public let errors: [String]

    public init(pushed: Int = 0, pulled: Int = 0, conflictsResolved: Int = 0, errors: [String] = []) {
        self.pushed = pushed
        self.pulled = pulled
        self.conflictsResolved = conflictsResolved
        self.errors = errors
    }
}

/// Current sync status.
public struct SyncStatus {
    public let enabled: Bool
    public let lastSuccessMs: Int64?
    public let pendingUploadCount: Int
    public let pendingDownloadCount: Int
    public let cursor: String?

    public init(enabled: Bool, lastSuccessMs: Int64? = nil, pendingUploadCount: Int = 0,
                pendingDownloadCount: Int = 0, cursor: String? = nil) {
        self.enabled = enabled
        self.lastSuccessMs = lastSuccessMs
        self.pendingUploadCount = pendingUploadCount
        self.pendingDownloadCount = pendingDownloadCount
        self.cursor = cursor
    }
}
