import Foundation

/// Deterministic error codes for Synheart Core.
public enum SynheartCoreError: Error, CustomStringConvertible {
    case notConfigured(String? = nil)
    case invalidMode(String? = nil)
    case researchNotAllowed
    case sessionNotFound
    case sessionActive
    case noActiveSession
    case storageDisabled
    case syncDisabled
    case cryptoKeyUnavailable
    case modeForbidsStream

    public var code: String {
        switch self {
        case .notConfigured:        return "ERR_NOT_CONFIGURED"
        case .invalidMode:          return "ERR_INVALID_MODE"
        case .researchNotAllowed:   return "ERR_RESEARCH_NOT_ALLOWED"
        case .sessionNotFound:      return "ERR_SESSION_NOT_FOUND"
        case .sessionActive:        return "ERR_SESSION_ACTIVE"
        case .noActiveSession:      return "ERR_NO_ACTIVE_SESSION"
        case .storageDisabled:      return "ERR_STORAGE_DISABLED"
        case .syncDisabled:         return "ERR_SYNC_DISABLED"
        case .cryptoKeyUnavailable: return "ERR_CRYPTO_KEY_UNAVAILABLE"
        case .modeForbidsStream:    return "ERR_MODE_FORBIDS_STREAM"
        }
    }

    public var description: String {
        switch self {
        case .notConfigured(let msg):
            return "SynheartCoreError(\(code)): \(msg ?? "Synheart.initialize() must be called before this operation.")"
        case .invalidMode(let msg):
            return "SynheartCoreError(\(code)): \(msg ?? "The specified mode is not valid for this operation.")"
        case .researchNotAllowed:
            return "SynheartCoreError(\(code)): Research mode requires privacy.allowResearch to be true."
        case .sessionNotFound:
            return "SynheartCoreError(\(code)): No session found with the given session_id."
        case .sessionActive:
            return "SynheartCoreError(\(code)): Cannot start a new session while one is already active."
        case .noActiveSession:
            return "SynheartCoreError(\(code)): No active session. Call startSession() first."
        case .storageDisabled:
            return "SynheartCoreError(\(code)): Storage is disabled in the current configuration."
        case .syncDisabled:
            return "SynheartCoreError(\(code)): Sync is not enabled in the current configuration."
        case .cryptoKeyUnavailable:
            return "SynheartCoreError(\(code)): Encryption key is not available."
        case .modeForbidsStream:
            return "SynheartCoreError(\(code)): The current mode does not allow this stream type."
        }
    }
}
