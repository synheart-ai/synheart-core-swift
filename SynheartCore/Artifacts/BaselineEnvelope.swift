import Foundation

/// Stable discriminator for a typed baseline artifact.
public enum BaselineKind: String, CaseIterable, Sendable {
    case sessionHsiAxes = "session.hsi_axes"
    case sessionSrmMetrics = "session.srm_metrics"
    case longitudinalWear = "longitudinal.wear"

    public var isSessionScoped: Bool { rawValue.hasPrefix("session.") }
}

public enum SrmMetricStatus: String, Sendable {
    case empty = "EMPTY"
    case warming = "WARMING"
    case ready = "READY"
}

public struct BaselineEngineRef: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let configHash: String

    public init(name: String, version: String, configHash: String) {
        self.name = name
        self.version = version
        self.configHash = configHash
    }

    enum CodingKeys: String, CodingKey {
        case name, version
        case configHash = "config_hash"
    }
}

/// Coverage metadata used when comparing baseline snapshots.
public struct BaselineEnvelopeCoverage: Codable, Equatable, Sendable {
    public let windowStartMs: Int64
    public let windowEndMs: Int64
    public let observations: Int
    public let dimensionsPresent: Int
    public let dimensionsTotal: Int

    public init(
        windowStartMs: Int64,
        windowEndMs: Int64,
        observations: Int,
        dimensionsPresent: Int,
        dimensionsTotal: Int
    ) {
        self.windowStartMs = windowStartMs
        self.windowEndMs = windowEndMs
        self.observations = observations
        self.dimensionsPresent = dimensionsPresent
        self.dimensionsTotal = dimensionsTotal
    }

    enum CodingKeys: String, CodingKey {
        case windowStartMs = "window_start_ms"
        case windowEndMs = "window_end_ms"
        case observations
        case dimensionsPresent = "dimensions_present"
        case dimensionsTotal = "dimensions_total"
    }
}

public struct HsiAxesBaseline {
    public let schemaVersion: Int
    public let axes: [String: AxisStats]

    public init(schemaVersion: Int = 1, axes: [String: AxisStats]) {
        self.schemaVersion = schemaVersion
        self.axes = axes
    }

    public init(runtimeMap: [String: Any]) {
        schemaVersion = (runtimeMap["schema_version"] as? NSNumber)?.intValue ?? 1
        let rawAxes = runtimeMap["axes"] as? [String: Any] ?? [:]
        axes = rawAxes.reduce(into: [:]) { result, entry in
            guard let map = entry.value as? [String: Any],
                  let mean = (map["mean"] as? NSNumber)?.doubleValue,
                  let std = (map["std"] as? NSNumber)?.doubleValue,
                  let confidence = (map["confidence"] as? NSNumber)?.doubleValue else { return }
            result[entry.key] = AxisStats(mean: mean, std: std, confidence: confidence)
        }
    }

    public func toRuntimeMap() -> [String: Any] {
        [
            "schema_version": schemaVersion,
            "axes": axes.mapValues { ["mean": $0.mean, "std": $0.std, "confidence": $0.confidence] },
        ]
    }
}

public struct SrmMetricBaseline: Equatable, Sendable {
    public let muTilde: Double
    public let sigmaTilde: Double
    public let status: SrmMetricStatus
    public let effectiveSampleCount: Int

    public init(muTilde: Double, sigmaTilde: Double, status: SrmMetricStatus, effectiveSampleCount: Int) {
        self.muTilde = muTilde
        self.sigmaTilde = sigmaTilde
        self.status = status
        self.effectiveSampleCount = effectiveSampleCount
    }

    init(runtimeMap: [String: Any]) {
        muTilde = (runtimeMap["mu_tilde"] as? NSNumber)?.doubleValue ?? 0
        sigmaTilde = (runtimeMap["sigma_tilde"] as? NSNumber)?.doubleValue ?? 0
        status = SrmMetricStatus(rawValue: runtimeMap["status"] as? String ?? "") ?? .empty
        effectiveSampleCount = (runtimeMap["n_eff"] as? NSNumber)?.intValue ?? 0
    }

    func toRuntimeMap() -> [String: Any] {
        ["mu_tilde": muTilde, "sigma_tilde": sigmaTilde, "status": status.rawValue, "n_eff": effectiveSampleCount]
    }
}

public struct SessionSrmMetricsBaseline {
    public let schemaVersion: Int
    public let metrics: [String: SrmMetricBaseline]

    public init(schemaVersion: Int = 1, metrics: [String: SrmMetricBaseline]) {
        self.schemaVersion = schemaVersion
        self.metrics = metrics
    }

    public init(runtimeMap: [String: Any]) {
        schemaVersion = (runtimeMap["schema_version"] as? NSNumber)?.intValue ?? 1
        let raw = runtimeMap["metrics"] as? [String: Any] ?? [:]
        metrics = raw.reduce(into: [:]) { result, entry in
            guard let map = entry.value as? [String: Any] else { return }
            result[entry.key] = SrmMetricBaseline(runtimeMap: map)
        }
    }

    public func toRuntimeMap() -> [String: Any] {
        ["schema_version": schemaVersion, "metrics": metrics.mapValues { $0.toRuntimeMap() }]
    }
}

public struct LongitudinalWearBaseline {
    public let schemaVersion: Int
    public let reference: WearableReferenceView

    public init(schemaVersion: Int = 1, reference: WearableReferenceView) {
        self.schemaVersion = schemaVersion
        self.reference = reference
    }

    public init(runtimeMap: [String: Any]) {
        schemaVersion = (runtimeMap["schema_version"] as? NSNumber)?.intValue ?? 1
        reference = WearableReferenceView.fromJson(runtimeMap)
    }

    public func toRuntimeMap() -> [String: Any] {
        var dimensions = reference.dimensions
        if let median = reference.recentSleepScoreMedian {
            dimensions["recent_sleep_score_median"] = Double(median)
        }
        return [
            "schema_version": schemaVersion,
            "status": reference.status,
            "model_version": reference.modelVersion as Any,
            "dimensions": dimensions,
            "confidence": reference.confidence,
        ]
    }
}

public enum BaselineEnvelopeError: Error, Equatable {
    case missingField(String)
    case unknownKind(String)
    case kindMismatch(expected: BaselineKind, actual: BaselineKind)
    case invalidSessionScope
}

/// Kind-agnostic envelope with typed payload accessors.
public struct BaselineEnvelope {
    public let header: ArtifactHeader
    public let kind: BaselineKind
    public let kindSchemaVersion: Int
    public let computedAtMs: Int64
    public let engine: BaselineEngineRef
    public let coverage: BaselineEnvelopeCoverage
    public let payload: [String: Any]

    public init(
        header: ArtifactHeader,
        kind: BaselineKind,
        kindSchemaVersion: Int,
        computedAtMs: Int64,
        engine: BaselineEngineRef,
        coverage: BaselineEnvelopeCoverage,
        payload: [String: Any]
    ) throws {
        guard kind.isSessionScoped == (header.sessionId != nil) else {
            throw BaselineEnvelopeError.invalidSessionScope
        }
        self.header = header
        self.kind = kind
        self.kindSchemaVersion = kindSchemaVersion
        self.computedAtMs = computedAtMs
        self.engine = engine
        self.coverage = coverage
        self.payload = payload
    }

    public init(runtimeMap: [String: Any]) throws {
        guard let headerMap = runtimeMap["header"] as? [String: Any] else {
            throw BaselineEnvelopeError.missingField("header")
        }
        guard let kindWire = runtimeMap["kind"] as? String else {
            throw BaselineEnvelopeError.missingField("kind")
        }
        guard let kind = BaselineKind(rawValue: kindWire) else {
            throw BaselineEnvelopeError.unknownKind(kindWire)
        }
        guard let engineMap = runtimeMap["engine"] as? [String: Any],
              let coverageMap = runtimeMap["coverage"] as? [String: Any],
              let payload = runtimeMap["payload"] as? [String: Any] else {
            throw BaselineEnvelopeError.missingField("engine, coverage, or payload")
        }
        let header = try Self.decode(ArtifactHeader.self, from: headerMap)
        try self.init(
            header: header,
            kind: kind,
            kindSchemaVersion: (runtimeMap["kind_schema_version"] as? NSNumber)?.intValue ?? 1,
            computedAtMs: (runtimeMap["computed_at_ms"] as? NSNumber)?.int64Value ?? 0,
            engine: try Self.decode(BaselineEngineRef.self, from: engineMap),
            coverage: try Self.decode(BaselineEnvelopeCoverage.self, from: coverageMap),
            payload: payload
        )
    }

    public func hsiAxes() throws -> HsiAxesBaseline {
        guard kind == .sessionHsiAxes else { throw BaselineEnvelopeError.kindMismatch(expected: .sessionHsiAxes, actual: kind) }
        return HsiAxesBaseline(runtimeMap: payload)
    }

    public func srmMetrics() throws -> SessionSrmMetricsBaseline {
        guard kind == .sessionSrmMetrics else { throw BaselineEnvelopeError.kindMismatch(expected: .sessionSrmMetrics, actual: kind) }
        return SessionSrmMetricsBaseline(runtimeMap: payload)
    }

    public func longitudinalWear() throws -> LongitudinalWearBaseline {
        guard kind == .longitudinalWear else { throw BaselineEnvelopeError.kindMismatch(expected: .longitudinalWear, actual: kind) }
        return LongitudinalWearBaseline(runtimeMap: payload)
    }

    public func toRuntimeMap() throws -> [String: Any] {
        [
            "header": try Self.encode(header),
            "kind": kind.rawValue,
            "kind_schema_version": kindSchemaVersion,
            "computed_at_ms": computedAtMs,
            "engine": try Self.encode(engine),
            "coverage": try Self.encode(coverage),
            "payload": payload,
        ]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from map: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: map))
    }

    private static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

/// Thread-safe last-write-wins cache for the latest baseline of each kind.
public final class BaselineSnapshots {
    private let lock = NSLock()
    private var cacheByKind: [BaselineKind: BaselineEnvelope] = [:]

    public init() {}

    public func envelope(for kind: BaselineKind) -> BaselineEnvelope? {
        lock.withLock { cacheByKind[kind] }
    }

    public var all: [BaselineKind: BaselineEnvelope] {
        lock.withLock { cacheByKind }
    }

    public func cache(_ envelope: BaselineEnvelope) {
        lock.withLock { cacheByKind[envelope.kind] = envelope }
    }

    public func reset() {
        lock.withLock { cacheByKind.removeAll() }
    }

    @discardableResult
    public func hydrate(from response: [String: Any]) -> [BaselineEnvelope] {
        guard response["error"] == nil,
              let snapshots = response["snapshots"] as? [[String: Any]] else { return [] }
        let decoded = snapshots.compactMap { try? BaselineEnvelope(runtimeMap: $0) }
        decoded.forEach(cache)
        return decoded
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
