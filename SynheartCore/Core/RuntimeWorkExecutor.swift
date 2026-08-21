import Foundation

/// Moves potentially blocking native calls onto a dedicated serial queue.
///
/// The native runtime handle is intentionally retained inside an unchecked
/// box for the duration of the call. Serial execution prevents overlapping
/// network operations from using the same process-wide runtime concurrently.
enum RuntimeWorkExecutor {
    private static let queue = DispatchQueue(
        label: "ai.synheart.core.runtime-work",
        qos: .utility
    )

    private final class WorkItem<Output>: @unchecked Sendable {
        let operation: () -> Output

        init(operation: @escaping () -> Output) {
            self.operation = operation
        }
    }

    static func run<Output>(_ operation: @escaping () -> Output) async -> Output {
        let workItem = WorkItem(operation: operation)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: workItem.operation())
            }
        }
    }
}
