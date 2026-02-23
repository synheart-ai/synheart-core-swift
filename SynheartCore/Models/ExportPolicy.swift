import Foundation

/// Export policy aligned with synheart-flux HSV.
///
/// Mirrors Rust `ExportPolicy` — controls which domains, axes, and
/// confidence thresholds appear in exported HSI payloads.
///
/// Pass an `ExportPolicy` to filter readings
/// by domain, confidence threshold, or purpose.
public struct ExportPolicy {
    /// Include physiology domain readings in the export.
    public let includePhysiology: Bool

    /// Include behavior domain readings in the export.
    public let includeBehavior: Bool

    /// Include context domain readings in the export.
    public let includeContext: Bool

    /// Include the 64D embedding vector in the export.
    public let includeEmbedding: Bool

    /// Minimum confidence threshold for axis readings.
    public let minConfidence: Float

    /// Intended purposes for this export (e.g., "analytics", "display").
    public let purposes: [String]

    /// Include additional metadata in the HSI meta block.
    public let includeMeta: Bool

    public init(
        includePhysiology: Bool = true,
        includeBehavior: Bool = true,
        includeContext: Bool = true,
        includeEmbedding: Bool = true,
        minConfidence: Float = 0.0,
        purposes: [String] = [],
        includeMeta: Bool = true
    ) {
        self.includePhysiology = includePhysiology
        self.includeBehavior = includeBehavior
        self.includeContext = includeContext
        self.includeEmbedding = includeEmbedding
        self.minConfidence = minConfidence
        self.purposes = purposes
        self.includeMeta = includeMeta
    }

    /// Default policy: export everything, no filtering.
    public static let `default` = ExportPolicy()

    /// Minimal policy: physiology only, no embedding.
    public static let physiologyOnly = ExportPolicy(
        includeBehavior: false,
        includeContext: false,
        includeEmbedding: false
    )
}
