import Foundation

/// Bounded, thread-safe gate for content-addressed HSI state delivery.
final class HSIDeliveryDeduplicator {
    private let capacity: Int
    private let lock = NSLock()
    private var orderedIds: [String] = []
    private var seenIds: Set<String> = []

    init(capacity: Int = 512) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func shouldDeliver(json: String) -> Bool {
        guard let hsiId = Self.hsiId(in: json), !hsiId.isEmpty else {
            // Legacy payloads have no stable identity and must not be dropped.
            return true
        }

        lock.lock()
        defer { lock.unlock() }

        guard seenIds.insert(hsiId).inserted else { return false }
        orderedIds.append(hsiId)
        if orderedIds.count > capacity {
            seenIds.remove(orderedIds.removeFirst())
        }
        return true
    }

    func reset() {
        lock.lock()
        orderedIds.removeAll(keepingCapacity: true)
        seenIds.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private static func hsiId(in json: String) -> String? {
        guard let map = RuntimePayloadDecoder.dictionary(json),
              let meta = map["meta"] as? [String: Any],
              let ids = meta["ids"] as? [String: Any] else { return nil }
        return ids["hsi_id"] as? String
    }
}
