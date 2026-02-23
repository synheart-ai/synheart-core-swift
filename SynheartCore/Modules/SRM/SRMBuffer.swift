import Foundation

/// An accepted entry stored in the per-stratum buffer.
public struct BufferEntry {
    public let windowId: String
    public let metrics: [String: Double]
    public let observedAtUtc: Date

    /// Calendar day key (UTC) for distinct-day counting.
    public var dayKey: String {
        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents([.year, .month, .day], from: observedAtUtc)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}

/// Bounded per-stratum buffer with quality gating, outlier rejection,
/// oldest-first eviction, and deterministic median/MAD computation.
///
/// Implements SRM.pdf §4 (accept/reject) and §5 (buffer management).
public class SRMBuffer {
    public let stratum: SRMStratum
    private let config: SRMConfig

    /// Ordered list of accepted entries (oldest first).
    private var _entries: [BufferEntry] = []

    /// Cached per-metric references. Recomputed after every buffer mutation.
    private var cachedReference: [String: MetricReference] = [:]

    public init(stratum: SRMStratum, config: SRMConfig) {
        self.stratum = stratum
        self.config = config
    }

    // MARK: - Public API

    public var entries: [BufferEntry] { _entries }
    public var count: Int { _entries.count }

    public var distinctDays: Int {
        Set(_entries.map { $0.dayKey }).count
    }

    public var baselineStatus: SRMBaselineStatus {
        if _entries.count < config.mMin { return .empty }
        if _entries.count < config.mReady { return .warming }
        if distinctDays < config.dMin { return .warming }
        return .ready
    }

    public var reference: [String: MetricReference] { cachedReference }

    /// Submit a candidate window. Returns an `SRMResult`.
    public func submit(_ candidate: CandidateWindow) -> SRMResult {
        if candidate.hasInvalidValues {
            return reject("nan_or_inf")
        }

        if candidate.durationSeconds < config.durationThresholdSeconds {
            return reject("duration_below_threshold")
        }

        if candidate.qualityScore < config.qualityThreshold {
            return reject("quality_below_threshold")
        }

        let motionThreshold = config.motionThresholdFor(stratum)
        if candidate.motionScore > motionThreshold {
            return reject("motion_above_threshold")
        }

        if _entries.count >= config.mMin {
            for metric in config.trackedMetrics {
                guard let value = candidate.metrics[metric],
                      let ref = cachedReference[metric] else { continue }

                let denominator = max(ref.mad, config.epsilon)
                let z = (value - ref.median) / denominator
                if abs(z) > config.outlierKappa {
                    return reject("outlier_\(metric)")
                }
            }
        }

        if _entries.count >= config.bufferSize {
            _entries.removeFirst()
        }

        _entries.append(BufferEntry(
            windowId: candidate.windowId,
            metrics: candidate.metrics,
            observedAtUtc: candidate.observedAtUtc
        ))

        recomputeReference()

        return accept()
    }

    /// Restore buffer from serialized entries (snapshot restore).
    public func restore(_ entries: [BufferEntry]) {
        _entries = entries
        recomputeReference()
    }

    /// Clear all entries and cached reference.
    public func reset() {
        _entries.removeAll()
        cachedReference.removeAll()
    }

    // MARK: - Deterministic Statistics (SRM.pdf §5.2)

    /// Deterministic median: lower-middle for even counts.
    public static func deterministicMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return .nan }
        if n % 2 == 1 { return sorted[n / 2] }
        return sorted[n / 2 - 1] // lower-middle
    }

    /// MAD (Median Absolute Deviation).
    public static func deterministicMAD(_ values: [Double], median: Double) -> Double {
        let deviations = values.map { abs($0 - median) }
        return deterministicMedian(deviations)
    }

    // MARK: - Private

    private func recomputeReference() {
        var ref: [String: MetricReference] = [:]
        for metric in config.trackedMetrics {
            let values = _entries.compactMap { $0.metrics[metric] }
            if values.isEmpty { continue }
            let med = SRMBuffer.deterministicMedian(values)
            let mad = SRMBuffer.deterministicMAD(values, median: med)
            ref[metric] = MetricReference(median: med, mad: mad)
        }
        cachedReference = ref
    }

    private func reject(_ reason: String) -> SRMResult {
        SRMResult(
            accepted: false,
            rejectionReason: reason,
            baselineStatus: baselineStatus,
            reference: cachedReference.isEmpty ? nil : cachedReference,
            srmSnapshotId: snapshotId(),
            srmVersion: config.srmVersion
        )
    }

    private func accept() -> SRMResult {
        SRMResult(
            accepted: true,
            baselineStatus: baselineStatus,
            reference: cachedReference.isEmpty ? nil : cachedReference,
            srmSnapshotId: snapshotId(),
            srmVersion: config.srmVersion
        )
    }

    private func snapshotId() -> String {
        "srm_\(stratum.rawValue)_\(_entries.count)_\(Int(Date().timeIntervalSince1970 * 1000))"
    }
}
