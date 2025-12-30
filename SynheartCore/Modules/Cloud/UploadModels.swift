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
/// Contains subject info and HSI 1.0 snapshots.
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

/// Helper for encoding Any values
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let float as Float:
            try container.encode(float)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable value cannot be encoded"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}
