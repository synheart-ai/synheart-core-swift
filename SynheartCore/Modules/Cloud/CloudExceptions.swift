import Foundation

/// Base error for Cloud Connector operations
public enum CloudConnectorError: Error, LocalizedError {
    case consentRequired(String)
    case invalidSignature
    case rateLimitExceeded(retryAfter: Int)
    case schemaValidation
    case networkError(String)
    case generic(String)

    public var errorDescription: String? {
        switch self {
        case .consentRequired(let message):
            return "Consent required: \(message)"
        case .invalidSignature:
            return "request signature validation failed"
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded, retry after \(retryAfter) seconds"
        case .schemaValidation:
            return "HSI 1.1 schema validation failed"
        case .networkError(let message):
            return "Network error: \(message)"
        case .generic(let message):
            return message
        }
    }
}
