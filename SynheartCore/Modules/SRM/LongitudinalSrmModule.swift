import Foundation

/// Bridges wearable events into the native personal baselines.
///
/// Maps recognised event types to daily metric names (``DailyMetric``),
/// extracts the value in the unit the name ends with, and pushes it to the
/// runtime with `srm_push_wearable_daily` under the event's provider and the
/// person's local date. After a push it asks the runtime to rebuild the
/// wearable reference from the days before today.
///
/// Event fields with no daily metric (sleep efficiency, a single workout's
/// strain, stress) are not pushed: a per-workout strain is not the day's
/// strain, and the runtime refuses any name outside ``DailyMetric/all``.
public final class LongitudinalSrmModule {

    private struct MetricExtractor {
        let metric: String
        let payloadKey: String
        /// Payload value → value in the metric's unit; nil drops it.
        var convert: (Double) -> Double? = { $0 }
    }

    private static let eventMetricMap: [String: [MetricExtractor]] = [
        "sleep.summary.recorded": [
            MetricExtractor(metric: DailyMetric.sleepDurationS, payloadKey: "duration_seconds"),
            MetricExtractor(metric: DailyMetric.sleepDeepMin, payloadKey: "deep_sleep_seconds") { $0 / 60.0 },
            MetricExtractor(metric: DailyMetric.sleepRemMin, payloadKey: "rem_sleep_seconds") { $0 / 60.0 },
        ],
        "hrv.recorded": [
            MetricExtractor(metric: DailyMetric.overnightRmssdMs, payloadKey: "rmssd_ms"),
        ],
        "heart_rate.resting.recorded": [
            MetricExtractor(metric: DailyMetric.restingHrBpm, payloadKey: "bpm"),
        ],
        "recovery.summary.recorded": [
            MetricExtractor(metric: DailyMetric.vendorRecoveryFrac, payloadKey: "score",
                            convert: LongitudinalSrmModule.recoveryFraction),
            MetricExtractor(metric: DailyMetric.overnightRmssdMs, payloadKey: "hrv_rmssd_ms"),
            MetricExtractor(metric: DailyMetric.restingHrBpm, payloadKey: "resting_hr_bpm"),
        ],
    ]

    private let timeZone: () -> TimeZone

    public init(timeZone: @escaping () -> TimeZone = { .current }) {
        self.timeZone = timeZone
    }

    /// Ingest a canonical wearable event, extract its daily values, and push
    /// them to the runtime via `bridge`. No-op if `bridge` is nil or the event
    /// type is not mapped. Returns the number of values stored.
    @discardableResult
    public func ingestEvent(_ event: CanonicalWearableEvent, bridge: CoreRuntimeBridge?) -> Int {
        guard let extractors = Self.eventMetricMap[event.type], let bridge else { return 0 }

        let tz = timeZone()
        // A night belongs to the date the person wakes on, which is the local
        // date of the summary's end / observation time.
        let date = Synheart.localDate(event.observedAt, tz)

        var values: [(String, Double)] = []
        for extractor in extractors {
            guard let raw = event.payload[extractor.payloadKey] else { continue }
            let number: Double
            if let num = raw as? NSNumber {
                number = num.doubleValue
            } else if let str = raw as? String, let parsed = Double(str) {
                number = parsed
            } else {
                continue
            }
            guard let value = extractor.convert(number), value.isFinite else { continue }
            values.append((extractor.metric, value))
        }
        if event.type == "sleep.summary.recorded",
           let iso = event.payload["midpoint_time"] as? String,
           let hours = Self.midpointHours(iso, timeZone: tz) {
            values.append((DailyMetric.sleepMidpointH, hours))
        }

        var stored = 0
        for (metric, value) in values {
            let rc = bridge.srmPushWearableDaily(
                provider: event.provider, metric: metric,
                year: date.year, month: date.month, day: date.day,
                value: value, vendorSummary: true
            )
            if rc == 0 {
                stored += 1
            } else {
                SynheartLogger.log(
                    "[LongitudinalSrm] \(event.provider)/\(metric) on "
                    + "\(date.year)-\(date.month)-\(date.day) not stored (rc=\(rc.map(String.init) ?? "nil"))"
                )
            }
        }

        if stored > 0 {
            // The reference is built from the days before the given date, so
            // today keeps every complete day in and no day in its own baseline.
            let today = Synheart.localDate(Date(), tz)
            bridge.srmRefreshWearableReference(year: today.year, month: today.month, day: today.day)
        }
        return stored
    }

    /// Get the current wearable reference JSON from the native engine.
    public func getWearableReference(bridge: CoreRuntimeBridge?) -> String? {
        return bridge?.getWearableReference()
    }

    /// Providers report recovery either as a fraction (`0.72`) or as a
    /// percentage (`72`); the runtime takes the fraction. Anything outside
    /// `0...100` is not a recovery score and is dropped.
    static func recoveryFraction(_ score: Double) -> Double? {
        if score < 0 || score > 100 { return nil }
        return score > 1 ? score / 100.0 : score
    }

    /// Hours after local midnight of an ISO 8601 instant, `0..<24`.
    static func midpointHours(_ iso: String, timeZone: TimeZone) -> Double? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        g.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: iso) ?? g.date(from: iso) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0 + Double(c.second ?? 0) / 3600.0
    }
}
