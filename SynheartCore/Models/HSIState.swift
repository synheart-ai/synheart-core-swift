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

/// Typed HSI state emitted by `Synheart.onStateUpdate`.
public struct HSIState {
    public let subjectId: String
    public let timestampMs: Int64
    public let hsi: HSIAxes
    public let rawJson: String

    public init(subjectId: String, timestampMs: Int64, hsi: HSIAxes, rawJson: String) {
        self.subjectId = subjectId
        self.timestampMs = timestampMs
        self.hsi = hsi
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
            ?? Int64(Date().timeIntervalSince1970 * 1000)

        let hsiMap = (map["hsi"] as? [String: Any]) ?? map
        let sid = (map["subject_id"] as? String) ?? subjectId

        return HSIState(
            subjectId: sid,
            timestampMs: timestampMs,
            hsi: parseAxes(hsiMap),
            rawJson: json
        )
    }

    private static func parseAxes(_ map: [String: Any]) -> HSIAxes {
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
}
