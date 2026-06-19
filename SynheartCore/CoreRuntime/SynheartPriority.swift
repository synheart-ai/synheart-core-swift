// SPDX-License-Identifier: Apache-2.0
//
// Multi-source priority resolver — Swift bindings.
//
// Mirrors `synheart-core-flutter/lib/src/priority/synheart_priority.dart`
// in API shape. When the Synheart native runtime (5.4.0+) is loaded, all
// calls route through the FFI symbols. Older runtimes (or unit tests
// running headless) fall back to a pure-Swift in-memory store with
// the same semantics so consumer apps can still develop without a
// freshly-built native lib.

import Foundation

/// Metric types that can have per-metric priority overrides.
///
/// `wireName` is the string passed across the C ABI — it must stay
/// in sync with the Rust `MetricType::as_str()` and the Dart enum's
/// `wireName` field. **Renaming requires a runtime migration.**
public enum PriorityMetric: String, CaseIterable {
    case heartRate   = "heart_rate"
    case hrv         = "hrv"
    case steps       = "steps"
    case sleep       = "sleep"
    case calories    = "calories"
    case spo2        = "spo2"
    case temperature = "temperature"
    case stress      = "stress"

    public var wireName: String { rawValue }
}

/// Outcome of a single priority resolution.
public struct SourceResolution: Equatable {
    public let winner: String
    public let rank: Int
    public let alsoRan: [(provider: String, rank: Int)]

    public init(
        winner: String,
        rank: Int,
        alsoRan: [(provider: String, rank: Int)]
    ) {
        self.winner = winner
        self.rank = rank
        self.alsoRan = alsoRan
    }

    public static func == (lhs: SourceResolution, rhs: SourceResolution) -> Bool {
        guard lhs.winner == rhs.winner, lhs.rank == rhs.rank,
              lhs.alsoRan.count == rhs.alsoRan.count else { return false }
        for (a, b) in zip(lhs.alsoRan, rhs.alsoRan) {
            if a.provider != b.provider || a.rank != b.rank { return false }
        }
        return true
    }
}

/// Sentinel rank for unknown providers — matches `i32::MAX` in
/// `ProviderRank::UNRANKED` on the Rust side.
public let kPriorityUnranked: Int = Int(Int32.max)

/// Process-wide priority API. Construct one for the lifetime of the
/// runtime and reuse it.
///
/// Thread-safety: all native calls go through a runtime mutex. The
/// in-memory fallback uses a single `DispatchQueue` for serialization
/// so callers don't have to think about concurrency.
public final class SynheartPriority {

    // Symbol resolution lives in CoreRuntimeBridge so the FFI surface
    // stays in one place — mirrors Kotlin's CoreRuntimeNative pattern.

    // MARK: - Mode

    /// Force in-memory mode for tests by passing `forceInMemory: true`.
    public init(forceInMemory: Bool = false) {
        self.useNative = !forceInMemory && CoreRuntimeBridge._prioritySetProvider != nil
    }

    private let useNative: Bool
    private let queue = DispatchQueue(label: "ai.synheart.priority")
    private var providers: [String: Int] = [:]
    private var overrides: [String: Int] = [:] // key: "metric|provider"

    /// Whether calls route through the runtime FFI.
    public var usingNativeStore: Bool { useNative }

    // MARK: - API

    /// Set the global rank for a provider. Lower wins.
    /// - Throws: `PriorityError.emptyProvider` for empty names.
    public func setProviderPriority(_ provider: String, rank: Int) throws {
        guard !provider.isEmpty else { throw PriorityError.emptyProvider }

        if useNative {
            let rc = provider.withCString { p in
                CoreRuntimeBridge._prioritySetProvider?(p, Int32(rank)) ?? -1
            }
            if rc != 0 { throw PriorityError.runtimeRejected(code: Int(rc)) }
            return
        }
        queue.sync { providers[provider] = rank }
    }

    /// Set or clear the per-metric override. Pass `nil` for `rank` to
    /// clear; the metric falls back to the global rank.
    public func setMetricOverride(
        _ metric: PriorityMetric,
        provider: String,
        rank: Int?
    ) throws {
        guard !provider.isEmpty else { throw PriorityError.emptyProvider }

        if useNative {
            let rc = metric.wireName.withCString { m in
                provider.withCString { p in
                    CoreRuntimeBridge._prioritySetMetricOverride?(
                        m, p, rank == nil ? 0 : 1, Int32(rank ?? 0)
                    ) ?? -1
                }
            }
            if rc != 0 { throw PriorityError.runtimeRejected(code: Int(rc)) }
            return
        }
        queue.sync {
            let key = "\(metric.wireName)|\(provider)"
            if let r = rank {
                overrides[key] = r
            } else {
                overrides.removeValue(forKey: key)
            }
        }
    }

    /// Read the effective rank for `(metric, provider)`. Returns
    /// `kPriorityUnranked` for unknown providers.
    public func effectiveRank(_ metric: PriorityMetric, provider: String) -> Int {
        if useNative {
            return metric.wireName.withCString { m in
                provider.withCString { p in
                    Int(CoreRuntimeBridge._priorityEffectiveRank?(m, p) ?? Int32(kPriorityUnranked))
                }
            }
        }
        return queue.sync {
            let key = "\(metric.wireName)|\(provider)"
            return overrides[key] ?? providers[provider] ?? kPriorityUnranked
        }
    }

    /// Resolve the winning source for `metric` given a `[provider:
    /// sample_count]` map. Returns `nil` only when there is nothing to
    /// pick (empty input).
    public func resolve(
        _ metric: PriorityMetric,
        samplesByProvider: [String: Int]
    ) -> SourceResolution? {
        if samplesByProvider.isEmpty { return nil }

        if useNative {
            guard
                let jsonData = try? JSONSerialization.data(withJSONObject: samplesByProvider),
                let jsonStr = String(data: jsonData, encoding: .utf8)
            else { return nil }
            let cstr = metric.wireName.withCString { m -> UnsafeMutablePointer<CChar>? in
                jsonStr.withCString { j in
                    CoreRuntimeBridge._priorityResolve?(m, j)
                }
            }
            guard let raw = CoreRuntimeBridge.consumeCString(cstr) else { return nil }
            return parseResolveJson(raw)
        }
        return resolveInMemory(metric, samplesByProvider: samplesByProvider)
    }

    // MARK: - Private

    private func parseResolveJson(_ raw: String) -> SourceResolution? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let winner = obj["winner"] as? String else { return nil }
        let rank = (obj["rank"] as? Int) ?? kPriorityUnranked
        let alsoRanRaw = (obj["also_ran"] as? [[String: Any]]) ?? []
        let alsoRan = alsoRanRaw.compactMap { entry -> (provider: String, rank: Int)? in
            guard let p = entry["provider"] as? String,
                  let r = entry["rank"] as? Int else { return nil }
            return (provider: p, rank: r)
        }
        return SourceResolution(winner: winner, rank: rank, alsoRan: alsoRan)
    }

    private func resolveInMemory(
        _ metric: PriorityMetric,
        samplesByProvider: [String: Int]
    ) -> SourceResolution? {
        let candidates = samplesByProvider
            .filter { $0.value > 0 }
            .map { (provider, count) -> (provider: String, rank: Int, count: Int) in
                (provider, effectiveRank(metric, provider: provider), count)
            }
        if candidates.isEmpty { return nil }

        let sorted = candidates.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.count != b.count { return a.count > b.count }
            return a.provider < b.provider
        }
        let winner = sorted[0]
        let alsoRan = sorted.dropFirst().map { (provider: $0.provider, rank: $0.rank) }
        return SourceResolution(
            winner: winner.provider,
            rank: winner.rank,
            alsoRan: Array(alsoRan)
        )
    }
}

/// Errors thrown by the Swift priority API.
public enum PriorityError: Error, Equatable {
    /// Provider name was empty.
    case emptyProvider
    /// Runtime returned a non-zero error code.
    case runtimeRejected(code: Int)
}
