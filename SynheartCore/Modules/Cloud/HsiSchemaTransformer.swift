import Foundation

/// Constants derived from hsi-1.1.schema.json.
///
/// When the HSI schema is upgraded, update `version`, add/modify the
/// domain and field sets, and the HsiSchemaTransformer adapts automatically.
public enum HsiSchema {
    public static let version = "1.1"

    /// Valid top-level axis domain names (additionalProperties: false on `axes`).
    public static let axisDomains: Set<String> = [
        "physiological",
        "behavior",
        "engagement",
        "context"
    ]

    /// Valid source types.
    public static let sourceTypes: Set<String> = [
        "sensor",
        "app",
        "self_report",
        "observer",
        "derived",
        "other"
    ]

    /// Valid direction values for axis readings.
    public static let directions: Set<String> = [
        "higher_is_more",
        "higher_is_less",
        "bidirectional"
    ]

    /// Valid embedding encoding formats.
    public static let encodings: Set<String> = [
        "float32",
        "float64",
        "fp16",
        "int8"
    ]

    /// Valid privacy consent level values.
    public static let consentLevels: Set<String> = [
        "none",
        "implicit",
        "explicit"
    ]

    /// Allowed fields on `axis_reading` (additionalProperties: false).
    public static let readingFields: Set<String> = [
        "axis",
        "score",
        "confidence",
        "window_id",
        "direction",
        "unit",
        "evidence_source_ids",
        "notes"
    ]

    /// Allowed fields on `window` (additionalProperties: false).
    public static let windowFields: Set<String> = ["start", "end", "label"]

    /// Allowed fields on `producer` (additionalProperties: false).
    public static let producerFields: Set<String> = [
        "name",
        "version",
        "instance_id"
    ]

    /// Allowed fields on `privacy` (additionalProperties: false).
    public static let privacyFields: Set<String> = [
        "contains_pii",
        "raw_biosignals_allowed",
        "derived_metrics_allowed",
        "embedding_allowed",
        "consent",
        "purposes",
        "notes"
    ]

    /// Allowed fields on `source` (additionalProperties: false).
    public static let sourceFields: Set<String> = [
        "type",
        "quality",
        "degraded",
        "notes"
    ]
}

/// Transforms raw HSI JSON maps produced by synheart-runtime into payloads
/// that conform to hsi-1.1.schema.json (additionalProperties: false).
///
/// The Rust runtime may produce slightly non-conformant output (e.g. extra
/// fields on readings or windows). This class patches the map in-place,
/// stripping anything that would fail schema validation.
public class HsiSchemaTransformer {

    public init() {}

    /// Patch `hsi` in-place to conform to hsi-1.1.schema.json.
    @discardableResult
    public func patch(_ hsi: inout [String: Any]) -> [String: Any] {
        hsi["hsi_version"] = HsiSchema.version
        patchProducer(&hsi)
        patchSources(&hsi)
        patchAxes(&hsi)
        patchWindows(&hsi)
        patchPrivacy(&hsi)
        return hsi
    }

    // MARK: - Private Patchers

    private func patchProducer(_ hsi: inout [String: Any]) {
        guard var producer = hsi["producer"] as? [String: Any] else { return }

        if producer["instance_id"] == nil {
            producer["instance_id"] = UUID().uuidString
        }

        producer = producer.filter { HsiSchema.producerFields.contains($0.key) }
        hsi["producer"] = producer
    }

    /// Ensure `source_ids` + `sources` pair integrity at top level.
    /// Both are optional, but if one is present the other must be too.
    private func patchSources(_ hsi: inout [String: Any]) {
        let sourceIds = hsi["source_ids"] as? [Any]
        var sourcesMap = hsi["sources"] as? [String: Any]

        let hasSourceIds = sourceIds != nil && !(sourceIds!.isEmpty)
        let hasSources = sourcesMap != nil && !(sourcesMap!.isEmpty)

        if hasSourceIds && !hasSources {
            hsi.removeValue(forKey: "source_ids")
        } else if !hasSourceIds && hasSources {
            hsi["source_ids"] = Array(sourcesMap!.keys)
        }

        // Ensure source_ids is [String] if present
        if let patchedSourceIds = hsi["source_ids"] as? [Any] {
            let strings = patchedSourceIds.compactMap { $0 as? String }
            if strings.isEmpty {
                hsi.removeValue(forKey: "source_ids")
            } else {
                hsi["source_ids"] = strings
            }
        }

        if var srcMap = hsi["sources"] as? [String: Any] {
            for (key, value) in srcMap {
                guard var entry = value as? [String: Any] else { continue }

                entry = entry.filter { HsiSchema.sourceFields.contains($0.key) }

                if let type = entry["type"] as? String, !HsiSchema.sourceTypes.contains(type) {
                    entry["type"] = "derived"
                }

                srcMap[key] = entry
            }
            hsi["sources"] = srcMap
        }
    }

    private func patchAxes(_ hsi: inout [String: Any]) {
        guard var axes = hsi["axes"] as? [String: Any] else { return }

        // Drop unknown domains (additionalProperties: false).
        axes = axes.filter { HsiSchema.axisDomains.contains($0.key) }

        for (domainKey, domainValue) in axes {
            guard var domain = domainValue as? [String: Any] else { continue }
            guard var readings = domain["readings"] as? [[String: Any]] else { continue }

            for i in 0..<readings.count {
                var reading = readings[i]

                reading = reading.filter { HsiSchema.readingFields.contains($0.key) }

                if let direction = reading["direction"] as? String,
                   !HsiSchema.directions.contains(direction) {
                    reading.removeValue(forKey: "direction")
                }

                if let evidence = reading["evidence_source_ids"] as? [Any] {
                    let strings = evidence.compactMap { $0 as? String }
                    if strings.isEmpty {
                        reading.removeValue(forKey: "evidence_source_ids")
                    } else {
                        reading["evidence_source_ids"] = strings
                    }
                }

                readings[i] = reading
            }

            domain["readings"] = readings
            axes[domainKey] = domain
        }

        hsi["axes"] = axes
    }

    private func patchWindows(_ hsi: inout [String: Any]) {
        guard var windows = hsi["windows"] as? [String: Any] else { return }

        for (key, value) in windows {
            guard var window = value as? [String: Any] else { continue }
            window = window.filter { HsiSchema.windowFields.contains($0.key) }
            windows[key] = window
        }

        hsi["windows"] = windows
    }

    private func patchPrivacy(_ hsi: inout [String: Any]) {
        guard var privacy = hsi["privacy"] as? [String: Any] else { return }

        // Normalize consent field
        if let consent = privacy["consent"] as? [String: Any] {
            privacy["consent"] = (consent["level"] as? String) ?? "explicit"
        } else if let consent = privacy["consent"] as? String {
            if !HsiSchema.consentLevels.contains(consent) {
                privacy["consent"] = "explicit"
            }
        }

        if let patchedConsent = privacy["consent"] as? String,
           !HsiSchema.consentLevels.contains(patchedConsent) {
            privacy["consent"] = "explicit"
        }

        privacy["contains_pii"] = false
        if privacy["raw_biosignals_allowed"] == nil {
            privacy["raw_biosignals_allowed"] = false
        }
        if privacy["derived_metrics_allowed"] == nil {
            privacy["derived_metrics_allowed"] = true
        }

        privacy = privacy.filter { HsiSchema.privacyFields.contains($0.key) }
        hsi["privacy"] = privacy
    }
}
