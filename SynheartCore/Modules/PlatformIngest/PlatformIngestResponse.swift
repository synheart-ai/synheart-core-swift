import Foundation

/// Response from platform ingestion API calls.
public struct PlatformIngestResponse {
    public let success: Bool
    public let statusCode: Int
    public let body: [String: Any]?
    public let errorMessage: String?

    public init(
        success: Bool,
        statusCode: Int,
        body: [String: Any]? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.statusCode = statusCode
        self.body = body
        self.errorMessage = errorMessage
    }
}

extension PlatformIngestResponse: CustomStringConvertible {
    public var description: String {
        var base = "PlatformIngestResponse(success=\(success), statusCode=\(statusCode)"
        if let errorMessage = errorMessage {
            base += ", error=\(errorMessage)"
        }
        return base + ")"
    }
}
