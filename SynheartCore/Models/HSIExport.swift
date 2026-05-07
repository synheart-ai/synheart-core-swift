import Foundation

// MARK: - HSI Snapshot

/// HSI Snapshot — versioned JSON snapshot produced by synheart-engine.
///
/// This is the serializable, transport-safe, cloud-ingestable representation
/// of human state. HSI generation is handled exclusively by synheart-engine
/// the Core SDK receives the finished
/// JSON string via `CoreRuntimeBridge` and wraps it here for type safety.
public struct HSISnapshot {
    /// The complete HSI payload as a JSON-compatible dictionary.
    public let payload: [String: Any]

    public init(payload: [String: Any]) {
        self.payload = payload
    }

    /// HSI version (e.g., "1.1").
    public var hsiVersion: String {
        payload["hsi_version"] as? String ?? "1.1"
    }

    /// When the human state was observed.
    public var observedAtUtc: String? {
        payload["observed_at_utc"] as? String
    }

    /// When this payload was computed.
    public var computedAtUtc: String? {
        payload["computed_at_utc"] as? String
    }

    /// Axes readings (physiological, engagement, behavior, context).
    public var axes: [String: Any]? {
        payload["axes"] as? [String: Any]
    }

    /// Embedding vectors.
    public var embeddings: [[String: Any]]? {
        payload["embeddings"] as? [[String: Any]]
    }

    /// Privacy assertions.
    public var privacy: [String: Any]? {
        payload["privacy"] as? [String: Any]
    }

    /// Additional metadata.
    public var meta: [String: Any]? {
        payload["meta"] as? [String: Any]
    }
}
