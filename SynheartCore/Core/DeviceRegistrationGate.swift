import Foundation

/// Coalesces concurrent device registration requests into one native attempt.
///
/// Registration is idempotent server-side, but coalescing prevents avoidable
/// attestation, keychain, and network work when several app features become
/// ready at the same time.
actor DeviceRegistrationGate {
    private var activeAttempt: Task<DeviceRegistrationResult, Never>?

    func run(
        _ operation: @escaping () async -> DeviceRegistrationResult
    ) async -> DeviceRegistrationResult {
        if let activeAttempt {
            return await activeAttempt.value
        }

        let attempt = Task {
            await operation()
        }
        activeAttempt = attempt
        let result = await attempt.value
        activeAttempt = nil
        return result
    }
}
