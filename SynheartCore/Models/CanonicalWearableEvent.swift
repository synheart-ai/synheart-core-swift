import Foundation
import CryptoKit

/// A canonical wearable event from a health data provider.
public struct CanonicalWearableEvent {
    public let eventId: String
    public let subjectId: String
    public let deviceInstallId: String
    public let eventClass: String
    public let type: String
    public let provider: String
    public let providerRecordId: String?
    public let observedAt: Date
    public let ingestedAt: Date
    public let effectiveStart: Date?
    public let effectiveEnd: Date?
    public let payload: [String: Any]
    public let unit: String?
    public let confidence: Double
    public let sourceFidelity: String
    public let provenance: [String: Any]?
    public let schemaVersion: Int

    public init(
        eventId: String,
        subjectId: String,
        deviceInstallId: String,
        eventClass: String,
        type: String,
        provider: String,
        providerRecordId: String? = nil,
        observedAt: Date,
        ingestedAt: Date,
        effectiveStart: Date? = nil,
        effectiveEnd: Date? = nil,
        payload: [String: Any],
        unit: String? = nil,
        confidence: Double,
        sourceFidelity: String,
        provenance: [String: Any]? = nil,
        schemaVersion: Int = 1
    ) {
        self.eventId = eventId
        self.subjectId = subjectId
        self.deviceInstallId = deviceInstallId
        self.eventClass = eventClass
        self.type = type
        self.provider = provider
        self.providerRecordId = providerRecordId
        self.observedAt = observedAt
        self.ingestedAt = ingestedAt
        self.effectiveStart = effectiveStart
        self.effectiveEnd = effectiveEnd
        self.payload = payload
        self.unit = unit
        self.confidence = confidence
        self.sourceFidelity = sourceFidelity
        self.provenance = provenance
        self.schemaVersion = schemaVersion
    }

    // MARK: - Deterministic Event ID

    /// Compute a deterministic wearable event ID using synheart-id canonical format.
    ///
    /// If `providerRecordId` is present:
    ///   canonical = "kind=wearable_event|provider={provider}|provider_record_id={id}|v=1"
    /// Otherwise:
    ///   canonical = "effective_end={end_or_~}|effective_start={start_or_~}|kind=wearable_event|observed={observedAt}|provider={provider}|subject={subjectId}|type={type}|v=1"
    ///
    /// SHA-256 -> first 24 bytes -> hex -> prefix "we_".
    public static func computeEventId(
        subjectId: String,
        type: String,
        provider: String,
        providerRecordId: String? = nil,
        observedAt: Date,
        effectiveStart: Date? = nil,
        effectiveEnd: Date? = nil
    ) -> String {
        let canonical: String
        if let recordId = providerRecordId {
            canonical = "kind=wearable_event|provider=\(provider)|provider_record_id=\(recordId)|v=1"
        } else {
            let endStr = effectiveEnd.map { iso8601String($0) } ?? "~"
            let startStr = effectiveStart.map { iso8601String($0) } ?? "~"
            canonical = "effective_end=\(endStr)|effective_start=\(startStr)|kind=wearable_event|observed=\(iso8601String(observedAt))|provider=\(provider)|subject=\(subjectId)|type=\(type)|v=1"
        }

        let digest = SHA256.hash(data: Data(canonical.utf8))
        let bytes = Array(digest)
        let truncated = bytes.prefix(24)
        let hex = truncated.map { String(format: "%02x", $0) }.joined()
        return "we_\(hex)"
    }

    // MARK: - Serialization

    public func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "event_id": eventId,
            "subject_id": subjectId,
            "device_install_id": deviceInstallId,
            "event_class": eventClass,
            "event_type": type,
            "provider": provider,
            "observed_at": CanonicalWearableEvent.iso8601String(observedAt),
            "ingested_at": CanonicalWearableEvent.iso8601String(ingestedAt),
            "confidence": confidence,
            "source_fidelity": sourceFidelity,
            "schema_version": schemaVersion,
        ]

        if let rid = providerRecordId { map["provider_record_id"] = rid }
        if let es = effectiveStart { map["effective_start"] = CanonicalWearableEvent.iso8601String(es) }
        if let ee = effectiveEnd { map["effective_end"] = CanonicalWearableEvent.iso8601String(ee) }
        if let u = unit { map["unit"] = u }

        if let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let payloadStr = String(data: payloadData, encoding: .utf8) {
            map["payload"] = payloadStr
        }

        if let prov = provenance,
           let provData = try? JSONSerialization.data(withJSONObject: prov),
           let provStr = String(data: provData, encoding: .utf8) {
            map["provenance"] = provStr
        }

        return map
    }

    public static func fromMap(_ map: [String: Any]) -> CanonicalWearableEvent? {
        guard let eventId = map["event_id"] as? String,
              let subjectId = map["subject_id"] as? String,
              let deviceInstallId = map["device_install_id"] as? String,
              let eventClass = map["event_class"] as? String,
              let type = map["event_type"] as? String,
              let provider = map["provider"] as? String,
              let observedAtStr = map["observed_at"] as? String,
              let ingestedAtStr = map["ingested_at"] as? String,
              let observedAt = parseIso8601(observedAtStr),
              let ingestedAt = parseIso8601(ingestedAtStr),
              let confidence = map["confidence"] as? Double,
              let sourceFidelity = map["source_fidelity"] as? String else {
            return nil
        }

        let payload: [String: Any]
        if let payloadStr = map["payload"] as? String,
           let data = payloadStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = parsed
        } else {
            payload = [:]
        }

        let provenance: [String: Any]?
        if let provStr = map["provenance"] as? String,
           let data = provStr.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            provenance = parsed
        } else {
            provenance = nil
        }

        let effectiveStart: Date?
        if let str = map["effective_start"] as? String { effectiveStart = parseIso8601(str) }
        else { effectiveStart = nil }

        let effectiveEnd: Date?
        if let str = map["effective_end"] as? String { effectiveEnd = parseIso8601(str) }
        else { effectiveEnd = nil }

        return CanonicalWearableEvent(
            eventId: eventId,
            subjectId: subjectId,
            deviceInstallId: deviceInstallId,
            eventClass: eventClass,
            type: type,
            provider: provider,
            providerRecordId: map["provider_record_id"] as? String,
            observedAt: observedAt,
            ingestedAt: ingestedAt,
            effectiveStart: effectiveStart,
            effectiveEnd: effectiveEnd,
            payload: payload,
            unit: map["unit"] as? String,
            confidence: confidence,
            sourceFidelity: sourceFidelity,
            provenance: provenance,
            schemaVersion: map["schema_version"] as? Int ?? 1
        )
    }

    // MARK: - ISO 8601 Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso8601String(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func parseIso8601(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }
}
