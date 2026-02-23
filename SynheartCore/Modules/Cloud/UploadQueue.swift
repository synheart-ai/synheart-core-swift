import Foundation

/// Persistent offline queue for String snapshots
///
/// Features:
/// - FIFO eviction when max size exceeded
/// - Persistent storage using UserDefaults
/// - Atomic batch operations
/// - Thread-safe queue operations
public actor UploadQueue {
    private var queue: [String] = []
    private let maxSize: Int
    private let storage: UserDefaults
    private let storageKey = "synheart_upload_queue"

    public init(maxSize: Int = 100, storage: UserDefaults = .standard) {
        self.maxSize = maxSize
        self.storage = storage
    }

    public var hasItems: Bool {
        !queue.isEmpty
    }

    public var length: Int {
        queue.count
    }

    /// Load queue from persistent storage
    public func loadFromStorage() {
        do {
            guard let data = storage.data(forKey: storageKey) else { return }

            let decoder = JSONDecoder()
            let items = try decoder.decode([String].self, from: data)
            queue = items

            print("[UploadQueue] Loaded \(queue.count) items from storage")
        } catch {
            print("[UploadQueue] Failed to load from storage: \(error)")
        }
    }

    /// Persist queue to storage
    func persistToStorage() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(queue)
            storage.set(data, forKey: storageKey)
        } catch {
            print("[UploadQueue] Failed to persist to storage: \(error)")
        }
    }

    /// Enqueue a new String snapshot
    ///
    /// Enforces max size with FIFO eviction.
    public func enqueue(_ hsiJson: String) {
        queue.append(hsiJson)

        // FIFO eviction if exceeding max size
        if queue.count > maxSize {
            queue.removeFirst()
        }

        persistToStorage()
    }

    /// Dequeue a batch of snapshots
    ///
    /// Returns up to `batchSize` items from the front of the queue.
    /// Items remain in queue until confirmBatch() is called.
    ///
    /// - Parameter batchSize: Maximum number of items to dequeue
    /// - Returns: Array of String snapshots (may be less than batchSize)
    public func dequeueBatch(_ batchSize: Int) -> [String] {
        guard !queue.isEmpty else { return [] }

        let count = min(queue.count, batchSize)
        return Array(queue.prefix(count))
    }

    /// Confirm batch was successfully uploaded (remove from queue)
    ///
    /// - Parameter batch: The batch that was successfully uploaded
    public func confirmBatch(_ batch: [String]) {
        // Remove the batch from the front of the queue
        let removeCount = min(batch.count, queue.count)
        queue.removeFirst(removeCount)
        persistToStorage()
    }

    /// Re-enqueue batch on failure
    ///
    /// Batch is still at the front of queue - just persist to ensure it's saved.
    ///
    /// - Parameter batch: The batch that failed to upload
    public func requeueBatch(_ batch: [String]) {
        // Batch is still at the front of queue - no action needed
        // Just persist to ensure it's saved
        persistToStorage()
    }

    /// Clear entire queue
    public func clear() {
        queue.removeAll()
        storage.removeObject(forKey: storageKey)
    }
}
