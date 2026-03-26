import Foundation

/// Subject information for upload payload
public struct Subject: Codable {
    public let subjectType: String
    public let subjectId: String

    enum CodingKeys: String, CodingKey {
        case subjectType = "subject_type"
        case subjectId = "subject_id"
    }

    public init(subjectType: String, subjectId: String) {
        self.subjectType = subjectType
        self.subjectId = subjectId
    }
}

/// Upload request payload
///
/// Contains subject info and HSI 1.1 snapshots.
public struct UploadRequest: Codable {
    public let subject: Subject
    public let snapshots: [[String: AnyCodable]]

    public init(subject: Subject, snapshots: [[String: AnyCodable]]) {
        self.subject = subject
        self.snapshots = snapshots
    }
}

/// Successful upload response
public struct UploadResponse: Codable {
    public let status: String
    public let snapshotId: String?
    public let timestamp: Int

    enum CodingKeys: String, CodingKey {
        case status
        case snapshotId = "snapshot_id"
        case timestamp
    }
}

/// Error response from upload endpoint
public struct UploadErrorResponse: Codable {
    public let status: String
    public let code: String
    public let message: String
    public let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case code
        case message
        case retryAfter = "retry_after"
    }
}

// AnyCodable is defined in Artifacts/HSIWindow.swift — shared across the SDK.
