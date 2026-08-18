import Foundation

/// A single HSI axis reading with value and confidence.
public struct HSIAxisValue: Codable {
    public let value: Double
    public let confidence: Double

    public init(value: Double, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }
}

/// The canonical HSI axes surfaced to hosts.
public struct HSIAxes: Codable {
    public let focus: HSIAxisValue?
    public let arousal: HSIAxisValue?
    public let capacity: HSIAxisValue?
    public let sleep: HSIAxisValue?
    /// Multimodal stress reading (motion-gated autonomic primary fused with a
    /// behavioral corroborator). New in engine v0.10.0; nil on the legacy/1.2
    /// path that never carried it.
    public let stress: HSIAxisValue?

    public init(focus: HSIAxisValue? = nil, arousal: HSIAxisValue? = nil,
                capacity: HSIAxisValue? = nil, sleep: HSIAxisValue? = nil,
                stress: HSIAxisValue? = nil) {
        self.focus = focus
        self.arousal = arousal
        self.capacity = capacity
        self.sleep = sleep
        self.stress = stress
    }
}

/// Signal modalities present in the HSI provenance block.
public struct HSIModalities: Equatable, Sendable {
    public let physiological: Bool
    public let kinematic: Bool
    public let digital: Bool

    public init(
        physiological: Bool = false,
        kinematic: Bool = false,
        digital: Bool = false
    ) {
        self.physiological = physiological
        self.kinematic = kinematic
        self.digital = digital
    }

    public var isEmpty: Bool { !physiological && !kinematic && !digital }
}

/// Per-modality source fidelity. Lower tiers represent higher fidelity.
public struct HSITiers: Equatable, Sendable {
    public let physiological: Int?
    public let kinematic: Int?
    public let digital: Int?

    public init(
        physiological: Int? = nil,
        kinematic: Int? = nil,
        digital: Int? = nil
    ) {
        self.physiological = physiological
        self.kinematic = kinematic
        self.digital = digital
    }

    public var isEmpty: Bool {
        physiological == nil && kinematic == nil && digital == nil
    }
}

/// Typed HSI state emitted by `Synheart.onStateUpdate`.
public struct HSIState {
    public let subjectId: String
    public let timestampMs: Int64
    public let hsiId: String?
    public let hsiVersion: String?
    public let hsi: HSIAxes
    public let modalities: HSIModalities
    public let tiers: HSITiers
    public let rawJson: String

    public init(
        subjectId: String,
        timestampMs: Int64,
        hsi: HSIAxes,
        rawJson: String,
        hsiId: String? = nil,
        hsiVersion: String? = nil,
        modalities: HSIModalities = HSIModalities(),
        tiers: HSITiers = HSITiers()
    ) {
        self.subjectId = subjectId
        self.timestampMs = timestampMs
        self.hsiId = hsiId
        self.hsiVersion = hsiVersion
        self.hsi = hsi
        self.modalities = modalities
        self.tiers = tiers
        self.rawJson = rawJson
    }

    /// Parse an HSI JSON string from the runtime into a typed HSIState.
    public static func fromJson(_ json: String, subjectId: String = "") -> HSIState {
        guard let data = json.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HSIState(subjectId: subjectId, timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                            hsi: HSIAxes(), rawJson: json)
        }

        let timestampMs = (map["timestamp_ms"] as? NSNumber)?.int64Value
            ?? (map["observed_at_ms"] as? NSNumber)?.int64Value
            ?? parseUtcMilliseconds(map["observed_at_utc"] as? String)
            ?? Int64(Date().timeIntervalSince1970 * 1000)

        let version = map["hsi_version"] as? String
        let axes: HSIAxes
        if version == "1.3" {
            axes = parseCanonicalAxes(map["axes"])
        } else {
            let hsiMap = (map["hsi"] as? [String: Any]) ?? map
            axes = parseLegacyAxes(hsiMap)
        }
        let sid = (map["subject_id"] as? String) ?? subjectId
        let ids = ((map["meta"] as? [String: Any])?["ids"] as? [String: Any])

        return HSIState(
            subjectId: sid,
            timestampMs: timestampMs,
            hsi: axes,
            rawJson: json,
            hsiId: ids?["hsi_id"] as? String,
            hsiVersion: version,
            modalities: deriveModalities(map),
            tiers: deriveTiers(map)
        )
    }

    private static func parseLegacyAxes(_ map: [String: Any]) -> HSIAxes {
        func parseAxis(_ key: String) -> HSIAxisValue? {
            guard let obj = map[key] as? [String: Any] else { return nil }
            return HSIAxisValue(
                value: (obj["value"] as? NSNumber)?.doubleValue ?? 0,
                confidence: (obj["confidence"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        return HSIAxes(
            focus: parseAxis("focus"),
            arousal: parseAxis("arousal"),
            capacity: parseAxis("capacity"),
            sleep: parseAxis("sleep"),
            stress: parseAxis("stress")
        )
    }

    private static func parseCanonicalAxes(_ value: Any?) -> HSIAxes {
        guard let axes = value as? [String: Any] else { return HSIAxes() }

        func reading(domain: String, name: String) -> HSIAxisValue? {
            guard let values = axes[domain] as? [Any] else { return nil }
            for case let item as [String: Any] in values where item["name"] as? String == name {
                guard let score = item["score"] as? NSNumber else { return nil }
                return HSIAxisValue(
                    value: score.doubleValue,
                    confidence: (item["confidence"] as? NSNumber)?.doubleValue ?? 0
                )
            }
            return nil
        }

        return HSIAxes(
            focus: reading(domain: "cognitive", name: "focus"),
            arousal: reading(domain: "affective", name: "arousal"),
            capacity: reading(domain: "cognitive", name: "capacity"),
            sleep: reading(domain: "physiological", name: "sleep_score")
                ?? reading(domain: "physiological", name: "sleep"),
            stress: reading(domain: "affective", name: "stress")
        )
    }

    private static func parseUtcMilliseconds(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { Int64($0.timeIntervalSince1970 * 1_000) }
    }

    private static func signalModality(_ signal: String) -> String? {
        switch signal {
        case "hrv", "rr", "ecg", "ppg", "spo2", "resp", "eda", "gsr", "temp", "hr":
            return "physiological"
        case "accel", "gyro", "mag":
            return "kinematic"
        case "touch", "scroll", "app_switch", "typing", "notification", "clipboard":
            return "digital"
        default:
            return nil
        }
    }

    private static func provenanceSources(_ map: [String: Any]) -> [[String: Any]] {
        guard let meta = map["meta"] as? [String: Any],
              let provenance = meta["provenance"] as? [String: Any],
              let sources = provenance["sources"] as? [String: Any] else { return [] }
        return sources.values.compactMap { $0 as? [String: Any] }
    }

    private static func deriveModalities(_ map: [String: Any]) -> HSIModalities {
        let modalities = Set(provenanceSources(map).flatMap { source in
            (source["signals"] as? [String] ?? []).compactMap(signalModality)
        })
        return HSIModalities(
            physiological: modalities.contains("physiological"),
            kinematic: modalities.contains("kinematic"),
            digital: modalities.contains("digital")
        )
    }

    private static func deriveTiers(_ map: [String: Any]) -> HSITiers {
        let physiological = provenanceSources(map).compactMap { source -> Int? in
            let signals = source["signals"] as? [String] ?? []
            guard signals.contains(where: { signalModality($0) == "physiological" }) else {
                return nil
            }
            return (source["source_tier"] as? NSNumber)?.intValue
        }.max()

        let tiers = (((map["meta"] as? [String: Any])?["synheart"] as? [String: Any])?["tiers"] as? [String: Any])
        return HSITiers(
            physiological: physiological,
            kinematic: (tiers?["kinematic"] as? NSNumber)?.intValue,
            digital: (tiers?["digital"] as? NSNumber)?.intValue
        )
    }
}
