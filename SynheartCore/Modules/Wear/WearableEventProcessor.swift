import Foundation

/// Processes incoming RAMEN vendor events into the SynHeart pipeline:
///   RamenEvent payload -> CanonicalWearableEvent -> SQLite store -> SRM push -> runtime
///
/// This is the bridge between the wear SDK's real-time event stream and the
/// core SDK's longitudinal SRM engine. Each vendor event (sleep, recovery,
/// HRV, strain) is normalized, stored immutably, and pushed to the runtime
/// for baseline computation.
public final class WearableEventProcessor {
    private let storage: StorageManager
    private let bridge: RuntimeBridge?
    private let srm: LongitudinalSrmModule
    private let subjectId: String
    private let deviceInstallId: String

    public init(
        storage: StorageManager,
        bridge: RuntimeBridge?,
        subjectId: String,
        deviceInstallId: String,
        srm: LongitudinalSrmModule? = nil
    ) {
        self.storage = storage
        self.bridge = bridge
        self.subjectId = subjectId
        self.deviceInstallId = deviceInstallId
        self.srm = srm ?? LongitudinalSrmModule()
    }

    // MARK: - Public API

    /// Process a raw vendor event from RAMEN.
    ///
    /// - Parameters:
    ///   - provider: e.g. "whoop", "garmin"
    ///   - eventType: e.g. "sleep.updated", "recovery.updated"
    ///   - payload: decoded JSON payload from the EventEnvelope
    ///   - eventId: RAMEN event ID (used for dedup)
    ///   - seq: RAMEN sequence number
    /// - Returns: The canonical event if processed, nil if skipped (unknown type or dedup).
    public func processRamenEvent(
        provider: String,
        eventType: String,
        payload: [String: Any],
        eventId: String,
        seq: Int
    ) -> CanonicalWearableEvent? {
        // Map RAMEN event type to canonical event type
        guard let mapping = mapEventType(provider: provider, eventType: eventType) else {
            SynheartLogger.log("[WearableEventProcessor] Unknown event type: \(provider)/\(eventType) -- skipping")
            return nil
        }

        // Extract timestamps
        let observedAt = extractTimestamp(payload, key: mapping.observedAtKey) ?? Date()
        let effectiveStart = extractTimestamp(payload, key: mapping.effectiveStartKey)
        let effectiveEnd = extractTimestamp(payload, key: mapping.effectiveEndKey)

        // Extract provider record ID for deterministic dedup
        let providerRecordId: String?
        if let key = mapping.providerRecordIdKey {
            providerRecordId = (payload[key] as? CustomStringConvertible)?.description
        } else {
            providerRecordId = nil
        }

        // Extract confidence from payload or use provider default
        let confidence = extractConfidence(payload, provider: provider)

        // Build canonical event
        let canonicalEventId = CanonicalWearableEvent.computeEventId(
            subjectId: subjectId,
            type: mapping.canonicalType,
            provider: provider,
            providerRecordId: providerRecordId,
            observedAt: observedAt,
            effectiveStart: effectiveStart,
            effectiveEnd: effectiveEnd
        )

        // Extract the sub-payload for the canonical event
        let canonicalPayload = mapping.extractPayload(payload)

        let event = CanonicalWearableEvent(
            eventId: canonicalEventId,
            subjectId: subjectId,
            deviceInstallId: deviceInstallId,
            eventClass: "PROVIDER_SUMMARY",
            type: mapping.canonicalType,
            provider: provider,
            providerRecordId: providerRecordId,
            observedAt: observedAt,
            ingestedAt: Date(),
            effectiveStart: effectiveStart,
            effectiveEnd: effectiveEnd,
            payload: canonicalPayload,
            confidence: confidence,
            sourceFidelity: "provider_summary",
            provenance: [
                "ramen_event_id": eventId,
                "ramen_seq": seq,
                "raw_event_type": eventType,
            ]
        )

        // Store (idempotent -- INSERT OR IGNORE on event_id)
        do {
            try storage.insertWearableEvent(event.toMap())
        } catch {
            SynheartLogger.log("[WearableEventProcessor] Storage error: \(error)")
            // Continue to SRM push even if storage fails -- runtime needs the data
        }

        // Push to longitudinal SRM via runtime bridge
        srm.ingestEvent(event, storage: storage, bridge: bridge)
        SynheartLogger.log(
            "[WearableEventProcessor] Processed \(provider)/\(mapping.canonicalType) "
            + "(seq=\(seq), confidence=\(String(format: "%.2f", confidence)))"
        )

        return event
    }

    // MARK: - Event Mapping

    private func mapEventType(provider: String, eventType: String) -> EventMapping? {
        let key = "\(provider):\(eventType)"
        return WearableEventProcessor.eventMappings[key]
            ?? WearableEventProcessor.eventMappings[eventType]
    }

    // MARK: - Timestamp Extraction

    private func extractTimestamp(_ payload: [String: Any], key: String?) -> Date? {
        guard let key = key, let raw = payload[key] else { return nil }
        if let str = raw as? String {
            return WearableEventProcessor.parseIso8601(str)
        }
        if let ms = raw as? Int {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        if let ms = raw as? Int64 {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return nil
    }

    // MARK: - Confidence Extraction

    private func extractConfidence(_ payload: [String: Any], provider: String) -> Double {
        // Some providers include quality/confidence in payload
        if let quality = payload["quality"] as? [String: Any],
           let conf = quality["confidence"] as? Double {
            return min(max(conf, 0.0), 1.0)
        }
        // Provider-level defaults (vendor summaries are generally high confidence)
        switch provider {
        case "whoop":  return 0.90
        case "garmin":  return 0.85
        case "oura":    return 0.88
        default:        return 0.75
        }
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

    private static func parseIso8601(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    // MARK: - Event Mapping Registry

    static let eventMappings: [String: EventMapping] = [
        // WHOOP events
        "whoop:recovery.updated": EventMapping(
            canonicalType: "recovery.summary.recorded",
            observedAtKey: "created_at",
            providerRecordIdKey: "cycle_id",
            extractPayload: { p in
                [
                    "score": asDouble(p["score"]) ?? asDouble(p["recovery_score"]) as Any,
                    "hrv_rmssd_ms": asDouble(p["hrv"]) as Any,
                    "resting_hr_bpm": asDouble(p["resting_heart_rate"]) as Any,
                    "spo2_pct": asDouble(p["spo2_percentage"]) as Any,
                ]
            }
        ),
        "whoop:sleep.updated": EventMapping(
            canonicalType: "sleep.summary.recorded",
            observedAtKey: "end",
            effectiveStartKey: "start",
            effectiveEndKey: "end",
            providerRecordIdKey: "id",
            extractPayload: { p in
                [
                    "duration_seconds": asInt(p["total_in_bed_time_milli"] ?? p["duration_seconds"]) as Any,
                    "efficiency_pct": asDouble(p["sleep_efficiency"]) as Any,
                    "midpoint_time": {
                        if let s = p["start"] as? String, let e = p["end"] as? String {
                            return midpointIso(start: s, end: e) as Any
                        }
                        return NSNull()
                    }() as Any,
                ]
            }
        ),
        "whoop:workout.updated": EventMapping(
            canonicalType: "workout.summary.recorded",
            observedAtKey: "end",
            effectiveStartKey: "start",
            effectiveEndKey: "end",
            providerRecordIdKey: "id",
            extractPayload: { p in
                [
                    "strain_score": asDouble(p["strain"]) ?? asDouble(p["score"]) as Any,
                    "duration_seconds": asInt(p["duration_seconds"]) as Any,
                    "avg_hr_bpm": asDouble(p["average_heart_rate"]) as Any,
                    "max_hr_bpm": asDouble(p["max_heart_rate"]) as Any,
                    "calories": asDouble(p["kilojoule"]) as Any,
                ]
            }
        ),

        // Garmin events
        "garmin:sleep.updated": EventMapping(
            canonicalType: "sleep.summary.recorded",
            observedAtKey: "calendarDate",
            providerRecordIdKey: "summaryId",
            extractPayload: { p in
                [
                    "duration_seconds": asInt(p["durationInSeconds"]) as Any,
                    "deep_sleep_seconds": asInt(p["deepSleepDurationInSeconds"]) as Any,
                    "light_sleep_seconds": asInt(p["lightSleepDurationInSeconds"]) as Any,
                    "rem_sleep_seconds": asInt(p["remSleepInSeconds"]) as Any,
                    "awake_seconds": asInt(p["awakeDurationInSeconds"]) as Any,
                ]
            }
        ),
        "garmin:recovery.updated": EventMapping(
            canonicalType: "recovery.summary.recorded",
            observedAtKey: "calendarDate",
            providerRecordIdKey: "summaryId",
            extractPayload: { p in
                var result: [String: Any] = [:]
                if let charged = asDouble(p["bodyBatteryChargedValue"]) {
                    result["score"] = charged / 100.0
                }
                result["stress_avg"] = asDouble(p["averageStressLevel"]) as Any
                result["resting_hr_bpm"] = asDouble(p["restingHeartRateInBeatsPerMinute"]) as Any
                return result
            }
        ),
        "garmin:hrv.updated": EventMapping(
            canonicalType: "hrv.recorded",
            observedAtKey: "calendarDate",
            providerRecordIdKey: "summaryId",
            extractPayload: { p in
                [
                    "rmssd_ms": asDouble(p["weeklyAvg"]) ?? asDouble(p["lastNightAvg"]) as Any,
                    "status": p["hrvStatus"] as Any,
                ]
            }
        ),

        // Generic fallbacks (provider-agnostic event types)
        "recovery.updated": EventMapping(
            canonicalType: "recovery.summary.recorded",
            observedAtKey: "created_at",
            extractPayload: { p in
                [
                    "score": asDouble(p["score"]) ?? asDouble(p["recovery_score"]) as Any,
                ]
            }
        ),
        "sleep.updated": EventMapping(
            canonicalType: "sleep.summary.recorded",
            observedAtKey: "end",
            effectiveStartKey: "start",
            effectiveEndKey: "end",
            extractPayload: { p in
                [
                    "duration_seconds": asInt(p["duration_seconds"]) as Any,
                    "efficiency_pct": asDouble(p["efficiency"]) as Any,
                ]
            }
        ),
    ]

    // MARK: - Type Coercion Helpers

    static func asDouble(_ value: Any?) -> Double? {
        guard let value = value else { return nil }
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String { return Double(str) }
        return nil
    }

    static func asInt(_ value: Any?) -> Int? {
        guard let value = value else { return nil }
        if let num = value as? NSNumber { return num.intValue }
        if let str = value as? String { return Int(str) }
        return nil
    }

    static func midpointIso(start: String, end: String) -> String? {
        guard let s = parseIso8601(start), let e = parseIso8601(end) else { return nil }
        let midInterval = s.timeIntervalSince1970 + (e.timeIntervalSince1970 - s.timeIntervalSince1970) / 2.0
        let mid = Date(timeIntervalSince1970: midInterval)
        return isoFormatter.string(from: mid)
    }
}

// MARK: - EventMapping

/// Configuration for mapping a RAMEN event type to a canonical event.
public struct EventMapping {
    public let canonicalType: String
    public let observedAtKey: String?
    public let effectiveStartKey: String?
    public let effectiveEndKey: String?
    public let providerRecordIdKey: String?
    public let extractPayload: ([String: Any]) -> [String: Any]

    public init(
        canonicalType: String,
        observedAtKey: String? = nil,
        effectiveStartKey: String? = nil,
        effectiveEndKey: String? = nil,
        providerRecordIdKey: String? = nil,
        extractPayload: @escaping ([String: Any]) -> [String: Any]
    ) {
        self.canonicalType = canonicalType
        self.observedAtKey = observedAtKey
        self.effectiveStartKey = effectiveStartKey
        self.effectiveEndKey = effectiveEndKey
        self.providerRecordIdKey = providerRecordIdKey
        self.extractPayload = extractPayload
    }
}
