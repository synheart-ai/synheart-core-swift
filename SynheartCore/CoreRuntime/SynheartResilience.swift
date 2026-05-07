// SPDX-License-Identifier: Apache-2.0
//
// HRV-CV resilience score — Swift bindings.
//
// Stateless wrapper around `synheart_core_resilience_compute_v1`.
// Mirror of `synheart-core-flutter/lib/src/resilience/synheart_resilience.dart`.
// When the runtime symbol is missing (older library, headless test
// builds without the compiled artifact), `compute()` throws
// `ResilienceError.runtimeUnavailable`.

import Foundation

// MARK: - Public types

/// One HRV sample at a point in time. Mirrors the Rust
/// `HrvSample` struct in `synheart-resilience`.
public struct HrvSample: Equatable {
    public let tsMs: Int64
    public let rmssdMs: Double

    public init(tsMs: Int64, rmssdMs: Double) {
        self.tsMs = tsMs
        self.rmssdMs = rmssdMs
    }

    var jsonObject: [String: Any] {
        ["ts_ms": tsMs, "rmssd_ms": rmssdMs]
    }
}

/// Half-open `[startMs, endMs)` interval representing a sleep window.
public struct SleepWindow: Equatable {
    public let startMs: Int64
    public let endMs: Int64

    public init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    var jsonObject: [String: Any] {
        ["start_ms": startMs, "end_ms": endMs]
    }
}

/// Tunable parameters. Defaults match the runtime's defaults.
public struct ResilienceConfig: Equatable {
    public var lookbackDays: Int
    public var minDaysRequired: Int
    public var minRrSamples: Int
    public var cvCeilingPct: Double
    public var cvFloorPct: Double

    public init(
        lookbackDays: Int = 7,
        minDaysRequired: Int = 5,
        minRrSamples: Int = 20,
        cvCeilingPct: Double = 7.0,
        cvFloorPct: Double = 40.0
    ) {
        self.lookbackDays = lookbackDays
        self.minDaysRequired = minDaysRequired
        self.minRrSamples = minRrSamples
        self.cvCeilingPct = cvCeilingPct
        self.cvFloorPct = cvFloorPct
    }

    var jsonObject: [String: Any] {
        [
            "lookback_days": lookbackDays,
            "min_days_required": minDaysRequired,
            "min_rr_samples": minRrSamples,
            "cv_ceiling_pct": cvCeilingPct,
            "cv_floor_pct": cvFloorPct,
        ]
    }
}

/// Why a resilience score might not be available.
public enum ResilienceReason: String {
    case insufficientDays
    case noSleepWindows
    case insufficientSamples
    case noValidSamples
    case zeroMeanHrv

    public static func fromWire(_ raw: String?) -> ResilienceReason? {
        switch raw {
        case "InsufficientDays":     return .insufficientDays
        case "NoSleepWindows":       return .noSleepWindows
        case "InsufficientSamples":  return .insufficientSamples
        case "NoValidSamples":       return .noValidSamples
        case "ZeroMeanHrv":          return .zeroMeanHrv
        default:                     return nil
        }
    }
}

/// Result returned by `compute()`. Mirrors the Rust
/// `ResilienceScoreResult`.
public struct ResilienceResult: Equatable {
    public let score: Int?
    public let rmssdOwMs: Double?
    public let sdnnOwMs: Double?
    public let hrvCvPct: Double?
    public let daysUsed: Int
    public let samplesUsed: Int
    public let confidence: Double
    public let reason: ResilienceReason?
    public let modelId: String
    public let pipelineVersion: String
    public let constantsHash: String

    public static func fromJson(_ obj: [String: Any]) -> ResilienceResult {
        let score = obj["score"] as? Int
        let rmssd = obj["rmssd_ow_ms"] as? Double
        let sdnn = obj["sdnn_ow_ms"] as? Double
        let cv = obj["hrv_cv_pct"] as? Double
        let days = (obj["days_used"] as? Int) ?? 0
        let samples = (obj["samples_used"] as? Int) ?? 0
        let confidence = (obj["confidence"] as? Double) ?? 0.0
        let reason = ResilienceReason.fromWire(obj["reason"] as? String)
        let modelId = (obj["model_id"] as? String) ?? ""
        let pipelineVersion = (obj["pipeline_version"] as? String) ?? ""
        let hash = (obj["constants_hash"] as? String) ?? ""
        return ResilienceResult(
            score: score,
            rmssdOwMs: rmssd,
            sdnnOwMs: sdnn,
            hrvCvPct: cv,
            daysUsed: days,
            samplesUsed: samples,
            confidence: confidence,
            reason: reason,
            modelId: modelId,
            pipelineVersion: pipelineVersion,
            constantsHash: hash
        )
    }
}

/// Errors thrown by the wrapper.
public enum ResilienceError: Error, Equatable {
    case runtimeUnavailable
    case computeFailed(message: String)
}

// MARK: - Wrapper

public final class SynheartResilience {

    // MARK: C aliases

    private typealias ComputeFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?

    private typealias FreeStringFn = @convention(c) (
        UnsafeMutablePointer<CChar>?
    ) -> Void

    private static func sym<T>(_ name: String) -> T? {
        let lib = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let _compute:    ComputeFn?    = sym("synheart_core_resilience_compute_v1")
    private static let _freeString: FreeStringFn? = sym("synheart_core_free_string")

    /// `forceUnavailable: true` skips the dlsym lookup — used by tests.
    public init(forceUnavailable: Bool = false) {
        self.useNative = !forceUnavailable && Self._compute != nil
    }

    private let useNative: Bool

    /// Whether the loaded runtime exposes the resilience symbol.
    public var isAvailable: Bool { useNative }

    // MARK: API

    /// Compute a resilience score over the given samples + sleep
    /// windows. Throws `.runtimeUnavailable` when the symbol is
    /// absent; throws `.computeFailed` when the runtime returns
    /// NULL or unparseable JSON.
    public func compute(
        samples: [HrvSample],
        sleepWindows: [SleepWindow],
        config: ResilienceConfig = ResilienceConfig()
    ) throws -> ResilienceResult {
        guard useNative else { throw ResilienceError.runtimeUnavailable }

        let samplesJson = try Self.encode(samples.map { $0.jsonObject })
        let windowsJson = try Self.encode(sleepWindows.map { $0.jsonObject })
        let configJson = try Self.encode(config.jsonObject)

        let resultPtr: UnsafeMutablePointer<CChar>? = samplesJson.withCString { s in
            windowsJson.withCString { w in
                configJson.withCString { c in
                    Self._compute?(s, w, c)
                }
            }
        }
        guard let cstr = resultPtr else {
            throw ResilienceError.computeFailed(
                message: "runtime returned NULL — likely malformed input"
            )
        }
        defer { Self._freeString?(cstr) }
        let raw = String(cString: cstr)
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ResilienceError.computeFailed(
                message: "could not parse runtime response: \(raw)"
            )
        }
        return ResilienceResult.fromJson(obj)
    }

    private static func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard let s = String(data: data, encoding: .utf8) else {
            throw ResilienceError.computeFailed(
                message: "JSON encoding produced non-utf8 bytes"
            )
        }
        return s
    }
}
