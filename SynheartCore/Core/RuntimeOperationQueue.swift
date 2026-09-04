import Foundation

/// One queue per native handle. Queued closures retain their native owner until
/// completion, including when the host disposes its facade in the meantime.
final class RuntimeOperationQueue {
    private let queue = DispatchQueue(label: "ai.synheart.core.handle-work", qos: .utility)

    private final class Work<Output>: @unchecked Sendable {
        let operation: () -> Output
        init(_ operation: @escaping () -> Output) { self.operation = operation }
    }

    func run<Output>(_ operation: @escaping () -> Output) async -> Output {
        let work = Work(operation)
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work.operation()) }
        }
    }
}
