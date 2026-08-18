import Foundation

/// Coalesces concurrent initialization requests into one attempt.
actor InitializationGate {
    private var activeAttempt: Task<Void, Error>?

    func run(_ operation: @escaping () async throws -> Void) async throws {
        if let activeAttempt {
            return try await activeAttempt.value
        }

        let attempt = Task {
            try await operation()
        }
        activeAttempt = attempt

        do {
            try await attempt.value
            activeAttempt = nil
        } catch {
            activeAttempt = nil
            throw error
        }
    }
}
