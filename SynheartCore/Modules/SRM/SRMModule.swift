import Foundation

/// SRM (Synheart Reference Model) module.
///
/// Maintains per-stratum bounded buffers of quality-gated candidate windows
/// and computes robust reference statistics (median/MAD) for each tracked
/// metric. This enables baseline-relative scoring when status reaches READY.
///
/// Implements RFC-CORE-0006 §3.3 and SRM.pdf.
public class SRMModule: BaseSynheartModule {
    private let config: SRMConfig
    private let storage: SRMSnapshotStorage?

    /// Per-stratum buffers.
    private var buffers: [SRMStratum: SRMBuffer] = [:]

    public init(config: SRMConfig = .defaults, storage: SRMSnapshotStorage? = nil) {
        self.config = config
        self.storage = storage
        super.init(moduleId: "srm")
    }

    // MARK: - Module lifecycle

    public override func onInitialize() async throws {
        print("[SRM] Initializing SRM module...")
        for stratum in SRMStratum.allCases {
            buffers[stratum] = SRMBuffer(stratum: stratum, config: config)
        }

        // Restore persisted snapshot if available
        if let storage = storage {
            do {
                if let saved = try storage.load() {
                    restoreSnapshot(saved)
                    print("[SRM] Restored persisted snapshot")
                }
            } catch {
                print("[SRM] Warning: failed to load persisted snapshot: \(error)")
            }
        }

        print("[SRM] SRM module initialized (\(buffers.count) strata)")
    }

    public override func onStart() async throws {
        print("[SRM] SRM module started")
    }

    public override func onStop() async throws {
        if let storage = storage {
            do {
                try storage.save(snapshot())
            } catch {
                print("[SRM] Warning: failed to persist snapshot on stop: \(error)")
            }
        }
        print("[SRM] SRM module stopped")
    }

    public override func onDispose() async throws {
        print("[SRM] Disposing SRM module...")
        if let storage = storage {
            do {
                try storage.save(snapshot())
            } catch {
                print("[SRM] Warning: failed to persist snapshot on dispose: \(error)")
            }
        }
        buffers.removeAll()
    }

    // MARK: - Public API (RFC-CORE-0006 §4.1)

    /// Submit a candidate window for SRM consideration.
    public func submitCandidate(_ candidate: CandidateWindow) -> SRMResult {
        guard let buffer = buffers[candidate.stratum] else {
            return SRMResult(
                accepted: false,
                rejectionReason: "unknown_stratum",
                baselineStatus: .empty,
                srmSnapshotId: "srm_unknown_0",
                srmVersion: config.srmVersion
            )
        }
        return buffer.submit(candidate)
    }

    /// Query the current reference for a stratum.
    public func queryReference(_ stratum: SRMStratum) -> SRMReference? {
        guard let buffer = buffers[stratum], buffer.count > 0 else { return nil }
        return SRMReference(
            stratum: stratum,
            status: buffer.baselineStatus,
            metrics: buffer.reference,
            bufferCount: buffer.count,
            distinctDays: buffer.distinctDays
        )
    }

    /// Get baseline status for a stratum.
    public func baselineStatus(_ stratum: SRMStratum) -> SRMBaselineStatus {
        buffers[stratum]?.baselineStatus ?? .empty
    }

    /// Get the overall baseline status (worst across all strata with data).
    public var overallBaselineStatus: SRMBaselineStatus {
        var worst = SRMBaselineStatus.ready
        var hasData = false
        for buffer in buffers.values {
            if buffer.count > 0 {
                hasData = true
                let s = buffer.baselineStatus
                if s.rawValue < worst.rawValue { worst = s }
            }
        }
        return hasData ? worst : .empty
    }

    /// Total number of accepted windows across all strata.
    public var totalAcceptedWindows: Int {
        buffers.values.reduce(0) { $0 + $1.count }
    }

    /// Total distinct calendar days across all strata.
    public var totalDistinctDays: Int {
        var days = Set<String>()
        for buffer in buffers.values {
            for entry in buffer.entries {
                days.insert(entry.dayKey)
            }
        }
        return days.count
    }

    /// Take an in-memory snapshot of all SRM state.
    public func snapshot() -> SRMSnapshot {
        var strata: [SRMStratum: StratumSnapshot] = [:]
        for (stratum, buffer) in buffers {
            strata[stratum] = StratumSnapshot(
                stratum: stratum,
                status: buffer.baselineStatus,
                entries: buffer.entries,
                reference: buffer.reference,
                distinctDays: buffer.distinctDays
            )
        }
        return SRMSnapshot(
            srmVersion: config.srmVersion,
            createdAtUtc: Date(),
            strata: strata
        )
    }

    /// Restore SRM state from a snapshot.
    public func restoreSnapshot(_ snapshot: SRMSnapshot) {
        if snapshot.srmVersion != config.srmVersion {
            print("[SRM] Warning: snapshot version \(snapshot.srmVersion) differs from config version \(config.srmVersion)")
        }
        for (stratum, stratumSnapshot) in snapshot.strata {
            buffers[stratum]?.restore(stratumSnapshot.entries)
        }
        print("[SRM] Restored snapshot (\(snapshot.strata.count) strata)")
    }

    /// Reset all buffers.
    public func reset() {
        for buffer in buffers.values {
            buffer.reset()
        }
        print("[SRM] All buffers reset")
    }

    /// Access to config (for integration modules that need thresholds).
    public func getConfig() -> SRMConfig { config }
}
