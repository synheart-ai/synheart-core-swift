import Foundation
import CommonCrypto

/// Compute a deterministic artifact ID from canonical fields.
///
/// Format: `{type}|v1|{subject_id}|{session_id_or_~}|{start_ms}|{end_ms}|{schema_name}@{schema_version}`
/// Result: SHA-256 hex digest of the canonical string (UTF-8 encoded).
///
/// See RFC-CORE-0006 Section 5.
public func computeArtifactId(
    type: String,
    subjectId: String,
    sessionId: String? = nil,
    startMs: Int64,
    endMs: Int64,
    schemaName: String,
    schemaVersion: String
) -> String {
    // Validate: no field may be empty, no field may contain '|'
    let fields = [type, subjectId, schemaName, schemaVersion]
    for field in fields {
        precondition(!field.isEmpty, "Artifact ID field must not be empty")
        precondition(!field.contains("|"), "Artifact ID field must not contain '|'")
    }
    if let sid = sessionId {
        precondition(!sid.contains("|"), "sessionId must not contain '|'")
    }

    let sessionField = sessionId ?? "~"
    let canonical = "\(type)|v1|\(subjectId)|\(sessionField)|\(startMs)|\(endMs)|\(schemaName)@\(schemaVersion)"

    return sha256Hex(canonical)
}

private func sha256Hex(_ string: String) -> String {
    let data = Data(string.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { ptr in
        _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}
