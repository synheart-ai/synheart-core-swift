import Foundation

public enum SyncOperation: Sendable {
    case createSpace, joinSpace, recoverSpace, generatePairing, syncNow
    case leaveSpace, listDevices, revokeDevice, deleteSpace, clearLocalSpace
}

public enum SyncReadinessCode: String, Sendable {
    case ready
    case nativeRuntimeUnavailable
    case featureNotActivated
    case cloudConsentRequired
    case capabilityNotAllowed
    case configurationMissing
    case storageUnavailable
    case deviceRevoked
    case deviceRegistrationRequired
    case activeSpaceRequired
    case srkUnavailable
}

public struct SyncReadiness {
    public let operation: SyncOperation
    public let isReady: Bool
    public let code: SyncReadinessCode
    public let nativeState: String?
    public let nativeSnapshot: [String: Any]?

    public init(
        operation: SyncOperation,
        isReady: Bool,
        code: SyncReadinessCode,
        nativeState: String?,
        nativeSnapshot: [String: Any]?
    ) {
        self.operation = operation
        self.isReady = isReady
        self.code = code
        self.nativeState = nativeState
        self.nativeSnapshot = nativeSnapshot
    }

    public static func evaluate(
        operation: SyncOperation,
        nativeSnapshot: [String: Any]?
    ) -> SyncReadiness {
        func result(_ ready: Bool, _ code: SyncReadinessCode) -> SyncReadiness {
            SyncReadiness(
                operation: operation,
                isReady: ready,
                code: code,
                nativeState: nativeSnapshot?["state"] as? String,
                nativeSnapshot: nativeSnapshot
            )
        }
        guard let nativeSnapshot else { return result(false, .nativeRuntimeUnavailable) }
        guard nativeSnapshot["configured"] as? Bool == true else { return result(false, .configurationMissing) }
        guard nativeSnapshot["storage_present"] as? Bool == true else { return result(false, .storageUnavailable) }
        if operation == .clearLocalSpace { return result(true, .ready) }
        guard nativeSnapshot["device_revoked"] as? Bool != true else { return result(false, .deviceRevoked) }
        guard nativeSnapshot["device_registered"] as? Bool == true else { return result(false, .deviceRegistrationRequired) }
        let bootstraps = operation == .createSpace || operation == .joinSpace || operation == .recoverSpace
        guard bootstraps || nativeSnapshot["active_space"] as? Bool == true else { return result(false, .activeSpaceRequired) }
        let requiresKey = operation == .generatePairing || operation == .syncNow
        guard !requiresKey || nativeSnapshot["srk_ready"] as? Bool == true else { return result(false, .srkUnavailable) }
        return result(true, .ready)
    }
}
