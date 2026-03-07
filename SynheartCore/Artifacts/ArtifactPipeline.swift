import Foundation

/// Bridges runtime HSI output to the artifact model and storage layer.
///
/// Accumulates HSI frames into 30-second windows, encrypts, and persists.
/// Produces SessionSummary on session close.
public final class ArtifactPipeline {
    private let storage: StorageManager
    private let policy: StoragePolicy
    private let smk: SMK
    private let subjectId: String
    private let appId: String
    private let appVersion: String
    private let deviceId: String
    private let platform: String

    private static let windowSizeMs: Int64 = 30000

    private var currentSessionId: String?
    private var currentMode: SynheartMode?
    private var windowStartMs: Int64?
    private var windowEndMs: Int64?
    private var windowHsiFrames: [[String: Any]] = []
    private var windowSeq = 0

    public init(
        storage: StorageManager,
        policy: StoragePolicy,
        smk: SMK,
        subjectId: String,
        appId: String,
        appVersion: String,
        deviceId: String,
        platform: String
    ) {
        self.storage = storage
        self.policy = policy
        self.smk = smk
        self.subjectId = subjectId
        self.appId = appId
        self.appVersion = appVersion
        self.deviceId = deviceId
        self.platform = platform
    }

    public func onSessionStart(_ sessionId: String, mode: SynheartMode) {
        currentSessionId = sessionId
        currentMode = mode
        windowStartMs = nil
        windowEndMs = nil
        windowHsiFrames.removeAll()
        windowSeq = 0
    }

    /// Ingest an HSI JSON frame from the runtime tick.
    public func ingestHsiFrame(_ hsiJson: String, timestampMs: Int64) throws -> HSIWindowArtifact? {
        guard currentSessionId != nil else { return nil }
        guard policy.canPersistArtifact("hsi_window") else { return nil }

        guard let data = hsiJson.data(using: .utf8),
              let hsiMap = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        windowHsiFrames.append(hsiMap)
        if windowStartMs == nil { windowStartMs = timestampMs }
        windowEndMs = timestampMs

        let elapsed = (windowEndMs ?? 0) - (windowStartMs ?? 0)
        if elapsed >= Self.windowSizeMs {
            return try finalizeWindow()
        }
        return nil
    }

    /// Flush any partial window (called on session stop).
    public func flushPendingWindow() throws -> HSIWindowArtifact? {
        guard !windowHsiFrames.isEmpty else { return nil }
        return try finalizeWindow()
    }

    private func finalizeWindow() throws -> HSIWindowArtifact? {
        guard !windowHsiFrames.isEmpty, let sessionId = currentSessionId else { return nil }

        let startMs = windowStartMs ?? 0
        let endMs = windowEndMs ?? 0
        let mergedHsi = windowHsiFrames.last ?? [:]

        let hsiAnyCodable = mergedHsi.mapValues { AnyCodable($0) }
        let artifact = HSIWindowArtifact.create(
            subjectId: subjectId,
            sessionId: sessionId,
            startMs: startMs,
            endMs: endMs,
            hsi: hsiAnyCodable,
            source: platform,
            deviceId: deviceId,
            appId: appId,
            runtimeVersion: "1.0.0"
        )

        let artifactJson = try artifactToJson(artifact)
        let encrypted = try ArtifactCrypto.encrypt(smk: smk, json: artifactJson)

        try storage.insertArtifact(ArtifactRecord(
            artifactId: artifact.header.artifactId,
            sessionId: sessionId,
            subjectId: subjectId,
            type: "hsi_window",
            schemaName: artifact.header.schema.name,
            schemaVersion: artifact.header.schema.version,
            startMs: startMs,
            endMs: endMs,
            seq: windowSeq,
            createdAtMs: artifact.header.createdAtMs,
            encAlg: encrypted.encAlg,
            payload: encrypted.ciphertext,
            payloadSha256: encrypted.sha256
        ))

        windowSeq += 1
        windowHsiFrames.removeAll()
        windowStartMs = nil
        windowEndMs = nil

        return artifact
    }

    /// Compute and persist a SessionSummary artifact.
    public func finalizeSession(sessionStartMs: Int64, sessionEndMs: Int64) throws -> SessionSummaryArtifact? {
        guard let sessionId = currentSessionId, let mode = currentMode else { return nil }
        guard policy.canPersistArtifact("session_summary") else { return nil }

        _ = try flushPendingWindow()

        let windowRecords = try storage.getArtifactsBySession(sessionId, type: "hsi_window")

        var hsiPayloads: [[String: Any]] = []
        for record in windowRecords {
            if let payload = try? ArtifactCrypto.decrypt(smk: smk, combined: record.payload) {
                hsiPayloads.append(payload)
            }
        }

        let aggregates = computeAggregates(hsiPayloads)
        let includeMetrics = policy.canIncludeMetrics()

        let artifact = SessionSummaryArtifact.create(
            subjectId: subjectId,
            sessionId: sessionId,
            startMs: sessionStartMs,
            endMs: sessionEndMs,
            mode: mode.rawValue,
            totalWindows: windowRecords.count,
            aggregates: aggregates,
            insightMetrics: includeMetrics ? InsightMetrics() : InsightMetrics()
        )

        let artifactJson = try artifactToJson(artifact)
        let encrypted = try ArtifactCrypto.encrypt(smk: smk, json: artifactJson)

        try storage.insertArtifact(ArtifactRecord(
            artifactId: artifact.header.artifactId,
            sessionId: sessionId,
            subjectId: subjectId,
            type: "session_summary",
            schemaName: artifact.header.schema.name,
            schemaVersion: artifact.header.schema.version,
            startMs: sessionStartMs,
            endMs: sessionEndMs,
            createdAtMs: artifact.header.createdAtMs,
            encAlg: encrypted.encAlg,
            payload: encrypted.ciphertext,
            payloadSha256: encrypted.sha256
        ))

        if let summaryData = try? JSONSerialization.data(withJSONObject: artifactJson),
           let summaryStr = String(data: summaryData, encoding: .utf8) {
            try storage.insertSummaryCache(
                sessionId: sessionId,
                artifactId: artifact.header.artifactId,
                summaryJson: summaryStr
            )
        }

        try storage.updateSession(sessionId, state: "closed", endUtc: sessionEndMs / 1000)

        currentSessionId = nil
        currentMode = nil

        return artifact
    }

    /// Produce a BaselineSnapshot from native runtime SRM export.
    public func produceBaselineSnapshot(_ srmSnapshotJson: String) throws -> BaselineSnapshotArtifact? {
        guard policy.canPersistArtifact("baseline_snapshot") else { return nil }
        guard let data = srmSnapshotJson.data(using: .utf8),
              let srmData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let axes = extractAxesFromSrm(srmData) else { return nil }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let coverageStartMs = (srmData["created_at_ms"] as? Int64) ?? (nowMs - 7 * 24 * 3600 * 1000)
        let totalWindows = countSrmWindows(srmData)

        let baseline = BaselineData(
            coverage: BaselineCoverage(startMs: coverageStartMs, endMs: nowMs, totalWindows: totalWindows),
            axes: axes,
            model: BaselineModelRef(
                modelId: (srmData["srm_version"] as? String) ?? "srm_v1",
                modelVersion: "1.0.0"
            )
        )

        let artifact = BaselineSnapshotArtifact.create(subjectId: subjectId, baseline: baseline)
        let artifactJson = try artifactToJson(artifact)
        let encrypted = try ArtifactCrypto.encrypt(smk: smk, json: artifactJson)

        try storage.insertArtifact(ArtifactRecord(
            artifactId: artifact.header.artifactId,
            subjectId: subjectId,
            type: "baseline_snapshot",
            schemaName: artifact.header.schema.name,
            schemaVersion: artifact.header.schema.version,
            startMs: coverageStartMs,
            endMs: nowMs,
            createdAtMs: artifact.header.createdAtMs,
            encAlg: encrypted.encAlg,
            payload: encrypted.ciphertext,
            payloadSha256: encrypted.sha256
        ))

        return artifact
    }

    // MARK: - Private helpers

    private func artifactToJson<T: Encodable>(_ artifact: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(artifact)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ArtifactPipeline", code: -1, userInfo: nil)
        }
        return dict
    }

    private func extractAxesFromSrm(_ srmData: [String: Any]) -> BaselineAxes? {
        guard let strata = srmData["strata"] as? [String: Any], !strata.isEmpty else { return nil }
        let restStratum = (strata["rest"] ?? strata.values.first) as? [String: Any]
        guard let stratum = restStratum else { return nil }

        let ref = stratum["reference"] as? [String: Any] ?? [:]
        let count = stratum["count"] as? Int ?? 0
        let confidence = count >= 50 ? 1.0 : Double(count) / 50.0

        func mean(_ key: String) -> Double {
            (ref[key] as? [String: Any])?["median"] as? Double ?? 0
        }
        func std(_ key: String) -> Double {
            (ref[key] as? [String: Any])?["mad"] as? Double ?? 0
        }

        return BaselineAxes(
            sleep: AxisStats(mean: mean("sleep"), std: std("sleep"), confidence: confidence),
            capacity: AxisStats(mean: mean("capacity"), std: std("capacity"), confidence: confidence),
            arousal: AxisStats(mean: mean("arousal"), std: std("arousal"), confidence: confidence),
            focus: AxisStats(mean: mean("focus"), std: std("focus"), confidence: confidence)
        )
    }

    private func countSrmWindows(_ srmData: [String: Any]) -> Int {
        guard let strata = srmData["strata"] as? [String: Any] else { return 0 }
        return strata.values.compactMap { ($0 as? [String: Any])?["count"] as? Int }.reduce(0, +)
    }

    private func computeAggregates(_ hsiPayloads: [[String: Any]]) -> SessionAggregates {
        let zero = AggregateAxis(mean: 0, min: 0, max: 0)
        guard !hsiPayloads.isEmpty else {
            return SessionAggregates(focus: zero, arousal: zero, capacity: zero, sleep: zero)
        }

        var fSum = 0.0, fMin = Double.infinity, fMax = -Double.infinity
        var aSum = 0.0, aMin = Double.infinity, aMax = -Double.infinity
        var cSum = 0.0, cMin = Double.infinity, cMax = -Double.infinity
        var sSum = 0.0, sMin = Double.infinity, sMax = -Double.infinity
        var count = 0

        for payload in hsiPayloads {
            guard let window = payload["window"] as? [String: Any],
                  let hsi = window["hsi"] as? [String: Any] else { continue }
            count += 1
            let f = (hsi["focus"] as? NSNumber)?.doubleValue ?? 0
            let a = (hsi["arousal"] as? NSNumber)?.doubleValue ?? 0
            let c = (hsi["capacity"] as? NSNumber)?.doubleValue ?? 0
            let s = (hsi["sleep"] as? NSNumber)?.doubleValue ?? 0

            fSum += f; fMin = Swift.min(fMin, f); fMax = Swift.max(fMax, f)
            aSum += a; aMin = Swift.min(aMin, a); aMax = Swift.max(aMax, a)
            cSum += c; cMin = Swift.min(cMin, c); cMax = Swift.max(cMax, c)
            sSum += s; sMin = Swift.min(sMin, s); sMax = Swift.max(sMax, s)
        }

        guard count > 0 else {
            return SessionAggregates(focus: zero, arousal: zero, capacity: zero, sleep: zero)
        }

        let n = Double(count)
        return SessionAggregates(
            focus: AggregateAxis(mean: fSum / n, min: fMin, max: fMax),
            arousal: AggregateAxis(mean: aSum / n, min: aMin, max: aMax),
            capacity: AggregateAxis(mean: cSum / n, min: cMin, max: cMax),
            sleep: AggregateAxis(mean: sSum / n, min: sMin, max: sMax)
        )
    }
}
