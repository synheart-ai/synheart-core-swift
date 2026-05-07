import Foundation

/// Bridges wearable events to the native longitudinal SRM engine via CoreRuntimeBridge.
///
/// Extracts daily dimension values from canonical wearable events and pushes them
/// to the native LongitudinalSrmEngine via C ABI. Triggers recompute after ingestion.
public final class LongitudinalSrmModule {

    private struct DimensionExtractor {
        let dimension: String
        let payloadKey: String
    }

    private static let eventDimensionMap: [String: [DimensionExtractor]] = [
        "sleep.summary.recorded": [
            DimensionExtractor(dimension: "sleep_need", payloadKey: "duration_seconds"),
            DimensionExtractor(dimension: "sleep_regularity", payloadKey: "midpoint_time"),
            DimensionExtractor(dimension: "sleep_efficiency", payloadKey: "efficiency_pct"),
        ],
        "hrv.recorded": [
            DimensionExtractor(dimension: "hrv_rmssd", payloadKey: "rmssd_ms"),
        ],
        "heart_rate.resting.recorded": [
            DimensionExtractor(dimension: "resting_hr", payloadKey: "bpm"),
        ],
        "recovery.summary.recorded": [
            DimensionExtractor(dimension: "recovery_score", payloadKey: "score"),
            DimensionExtractor(dimension: "hrv_rmssd", payloadKey: "hrv_rmssd_ms"),
            DimensionExtractor(dimension: "resting_hr", payloadKey: "resting_hr_bpm"),
        ],
        "workout.summary.recorded": [
            DimensionExtractor(dimension: "strain_score", payloadKey: "strain_score"),
        ],
        "stress.summary.recorded": [
            DimensionExtractor(dimension: "stress_score", payloadKey: "score"),
        ],
    ]

    public init() {}

    /// Ingest a canonical wearable event: extract daily values and push to the runtime via bridge.
    public func ingestEvent(_ event: CanonicalWearableEvent, bridge: CoreRuntimeBridge?) {
        guard let extractors = LongitudinalSrmModule.eventDimensionMap[event.type],
              let bridge = bridge else { return }

        let dayIndex = Int(event.observedAt.timeIntervalSince1970 / 86400)

        for extractor in extractors {
            guard let rawValue = event.payload[extractor.payloadKey] else { continue }

            let value: Double
            if let num = rawValue as? NSNumber {
                value = num.doubleValue
            } else if let str = rawValue as? String, let parsed = Double(str) {
                value = parsed
            } else {
                continue
            }

            bridge.pushWearableDailyValue(
                dimension: extractor.dimension,
                dayIndex: dayIndex,
                value: value,
                confidence: event.confidence,
                fidelity: LongitudinalSrmModule.fidelityToInt(event.sourceFidelity)
            )
        }

        let todayDayIndex = Int(Date().timeIntervalSince1970 / 86400)
        bridge.triggerWearableRecompute(triggerType: 0, asOfDay: todayDayIndex)
    }

    /// Get the current wearable reference JSON from the native engine.
    public func getWearableReference(bridge: CoreRuntimeBridge?) -> String? {
        return bridge?.getWearableReference()
    }

    private static func fidelityToInt(_ fidelity: String) -> Int32 {
        switch fidelity {
        case "raw":       return 0
        case "derived":   return 1
        case "estimated": return 2
        default:          return 2
        }
    }
}
