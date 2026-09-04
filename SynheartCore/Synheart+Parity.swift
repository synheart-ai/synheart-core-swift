import Foundation

public extension Synheart {
    // MARK: - Full sync lifecycle

    static func syncCreateSpace(deviceName: String? = nil) async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncCreateSpace(deviceName: deviceName ?? "") }
    }

    static func syncGeneratePairing() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncGeneratePairing() }
    }

    static func syncJoinSpace(pairingToken: String, deviceName: String? = nil) async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in
            bridge.syncJoinSpace(pairingToken: pairingToken, deviceName: deviceName ?? "")
        }
    }

    static var syncStatusSnapshot: [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        guard let raw = bridge.syncStatus(),
              let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static var syncReadinessSnapshot: [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return bridge.syncReadiness()
    }

    static func checkSyncReadiness(operation: SyncOperation) async -> SyncReadiness {
        let snapshot = shared.coreRuntime?.bridge?.syncReadiness()
        guard isActivated(.synsync) else {
            return SyncReadiness(
                operation: operation,
                isReady: false,
                code: .featureNotActivated,
                nativeState: snapshot?["state"] as? String,
                nativeSnapshot: snapshot
            )
        }
        guard await hasConsent(SynheartFeature.synsync.requiredConsent) else {
            return SyncReadiness(
                operation: operation,
                isReady: false,
                code: .cloudConsentRequired,
                nativeState: snapshot?["state"] as? String,
                nativeSnapshot: snapshot
            )
        }
        guard shared._isCapabilityAllowed(.synsync) else {
            return SyncReadiness(
                operation: operation,
                isReady: false,
                code: .capabilityNotAllowed,
                nativeState: snapshot?["state"] as? String,
                nativeSnapshot: snapshot
            )
        }
        return SyncReadiness.evaluate(operation: operation, nativeSnapshot: snapshot)
    }

    static func syncRecoverSpace(recoveryKey: String, spaceId: String) async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in
            bridge.syncRecoverSpace(recoveryKey: recoveryKey, spaceId: spaceId)
        }
    }

    static func syncLeaveSpace() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncLeaveSpace() }
    }

    static func syncListDevices() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncListDevices() }
    }

    static func syncRevokeDevice(deviceId: String) async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncRevokeDevice(deviceId: deviceId) }
    }

    static func syncDeleteSpace() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncDeleteSpace() }
    }

    static func syncClearLocalSpace() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.syncClearLocalSpace() }
    }

    // MARK: - Baseline transport and scores

    static func baselineHydrateLocal() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        let response = await bridge.performAsync { bridge in bridge.baselineHydrateLocal() }
        if let response { _ = baselineSnapshots.hydrate(from: response) }
        return response
    }

    static func baselineExportOffline(passphrase: String) async -> Data? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.baselineExportOffline(passphrase: passphrase) }
    }

    static func baselineImportOffline(passphrase: String, blob: Data) async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.baselineImportOffline(passphrase: passphrase, blob: blob) }
    }

    static func computeSleepScore(_ input: SleepScoreInput) -> SleepScoreResult? {
        guard let json = shared.coreRuntime?.bridge?.computeSleepScore(inputJson: input.toJsonString()) else { return nil }
        return try? SleepScoreResult.fromJsonString(json)
    }

    static func computeRecoveryScore(_ input: RecoveryScoreInput) -> RecoveryScoreResult? {
        guard let json = shared.coreRuntime?.bridge?.computeRecoveryScore(inputJson: input.toJsonString()) else { return nil }
        return try? RecoveryScoreResult.fromJsonString(json)
    }

    static func computeReadinessScore(_ input: ReadinessScoreInput) -> ReadinessScoreResult? {
        guard let json = shared.coreRuntime?.bridge?.computeReadinessScore(inputJson: input.toJsonString()) else { return nil }
        return try? ReadinessScoreResult.fromJsonString(json)
    }

    @discardableResult
    static func attachSleepScore(_ result: SleepScoreResult) -> Int32 {
        shared.coreRuntime?.bridge?.attachSleepScore(resultJson: result.toJsonString()) ?? -1
    }

    @discardableResult
    static func attachRecoveryScoreToday(_ score: Int) -> Int32 {
        shared.coreRuntime?.bridge?.attachRecoveryScoreToday(score) ?? -1
    }

    @discardableResult
    static func clearRecoveryScoreToday() -> Int32 {
        shared.coreRuntime?.bridge?.clearRecoveryScoreToday() ?? -1
    }

    static var lastSleepScoreSnapshot: [String: Any]? {
        shared.coreRuntime?.bridge?.lastSleepScore()
    }

    static func exportLongitudinalSnapshot() -> String? {
        shared.coreRuntime?.bridge?.ensurePipeline()
        return shared.coreRuntime?.bridge?.exportLongitudinalSnapshot()
    }

    @discardableResult
    static func loadLongitudinalSnapshot(_ snapshotJson: String) -> Int32 {
        shared.coreRuntime?.bridge?.ensurePipeline()
        return shared.coreRuntime?.bridge?.loadLongitudinalSnapshot(snapshotJson) ?? -1
    }

    // MARK: - Customer data deletion and research

    static func requestDataDeletion(
        reason: String? = nil,
        contact: String? = nil,
        dryRun: Bool = false
    ) async throws -> DataDeletionRequest {
        guard let bridge = shared.coreRuntime?.bridge else { throw SynheartError.notInitialized }
        guard let map = await RuntimeWorkExecutor.run({
            bridge.requestDataDeletion(reason: reason ?? "", contact: contact ?? "", dryRun: dryRun)
        }) else { throw SynheartError.runtimeOperationFailed("Data deletion API is unavailable") }
        try throwRuntimeMapError(map)
        return try DataDeletionRequest(runtimeMap: map)
    }

    static func dataDeletionStatus(_ requestId: String) async throws -> DataDeletionRequest {
        guard let bridge = shared.coreRuntime?.bridge else { throw SynheartError.notInitialized }
        guard let map = await RuntimeWorkExecutor.run({ bridge.getDataDeletion(requestId: requestId) }) else {
            throw SynheartError.runtimeOperationFailed("Data deletion status API is unavailable")
        }
        try throwRuntimeMapError(map)
        return try DataDeletionRequest(runtimeMap: map)
    }

    static func listDataDeletions(limit: Int32 = 50, offset: Int32 = 0) async throws -> DataDeletionList {
        guard let bridge = shared.coreRuntime?.bridge else { throw SynheartError.notInitialized }
        guard let map = await RuntimeWorkExecutor.run({ bridge.listDataDeletions(limit: limit, offset: offset) }) else {
            throw SynheartError.runtimeOperationFailed("Data deletion listing API is unavailable")
        }
        try throwRuntimeMapError(map)
        return try DataDeletionList(runtimeMap: map)
    }

    static func researchStudyStatus() async -> [String: Any]? {
        guard let bridge = shared.coreRuntime?.bridge else { return nil }
        return await bridge.performAsync { bridge in bridge.researchStudyStatus() }
    }

    static func recordStudyConsent(_ payload: [String: Any]) async throws -> [String: Any]? {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw SynheartError.runtimeOperationFailed("Study consent payload is not valid JSON")
        }
        guard let bridge = shared.coreRuntime?.bridge else { throw SynheartError.notInitialized }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(decoding: data, as: UTF8.self)
        return await bridge.performAsync { bridge in bridge.recordStudyConsent(payloadJson: json) }
    }

    // MARK: - Runtime inputs, vendor data, and HSI history

    static func pushRrBatch(
        anchorTimestampMs: Int64,
        intervalsMs: [Double],
        newestFirst: Bool = false,
        provider: String = "default_sensor"
    ) {
        shared.coreRuntime?.bridge?.pushRrBatch(
            anchorTimestampMs: anchorTimestampMs,
            intervalsMs: intervalsMs,
            newestFirst: newestFirst,
            provider: provider
        )
    }

    static func pushVendorHrv(
        timestampMs: Int64,
        rmssd: Double? = nil,
        sdnn: Double? = nil,
        stress: Double? = nil,
        recovery: Double? = nil
    ) {
        shared.coreRuntime?.bridge?.pushVendorHrv(
            timestampMs: timestampMs,
            rmssd: rmssd ?? -1,
            sdnn: sdnn ?? -1,
            stress: stress ?? -1,
            recovery: recovery ?? -1
        )
    }

    static func pushVendorVitals(timestampMs: Int64, spo2: Double? = nil, respiration: Double? = nil) {
        shared.coreRuntime?.bridge?.pushVendorVitals(
            timestampMs: timestampMs,
            spo2: spo2 ?? -1,
            respiration: respiration ?? -1
        )
    }

    static func ingestVendorEvent(_ event: CanonicalWearableEvent) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: event.toMap()),
              let json = String(data: data, encoding: .utf8) else { return false }
        return shared.coreRuntime?.bridge?.ingestVendorEvent(json: json) ?? false
    }

    static func queryVendorEvents(_ query: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: query),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return shared.coreRuntime?.bridge?.queryVendorEvents(queryJson: json)
    }

    static func latestVendorEvent(provider: String, eventType: String) -> [String: Any]? {
        shared.coreRuntime?.bridge?.latestVendorEvent(provider: provider, eventType: eventType)
    }

    @discardableResult
    static func deleteVendorEvents(provider: String) -> Int64 {
        shared.coreRuntime?.bridge?.deleteVendorEvents(provider: provider) ?? -1
    }

    static func listHsiHistory(since: Date? = nil, limit: Int64 = 0) -> [[String: Any]] {
        let sinceMs = Int64((since?.timeIntervalSince1970 ?? 0) * 1_000)
        return shared.coreRuntime?.bridge?.hsiHistory(sinceMs: sinceMs, limit: limit) ?? []
    }

    static func fetchCloudHsiWindows(from: Date, to: Date) async -> [[String: Any]] {
        guard let bridge = shared.coreRuntime?.bridge else { return [] }
        let fromMs = Int64(from.timeIntervalSince1970 * 1_000)
        let toMs = Int64(to.timeIntervalSince1970 * 1_000)
        return await bridge.performAsync { bridge in bridge.fetchCloudHsi(fromMs: fromMs, toMs: toMs) }
    }

    static var hsiHistoryCount: Int64 { shared.coreRuntime?.bridge?.hsiHistoryCount() ?? 0 }
    static func clearHsiHistory() -> Bool { shared.coreRuntime?.bridge?.clearHsiHistory() ?? false }

    // MARK: - Personalization

    static func setTaskType(_ task: TaskType) { shared.coreRuntime?.bridge?.setTaskType(task.rawValue) }
    static var currentTaskType: TaskType { TaskType.decode(shared.coreRuntime?.bridge?.currentTaskType() ?? 0) }
    static func setFocusKind(_ kind: FocusKind) { shared.coreRuntime?.bridge?.setFocusKind(kind.rawValue) }
    static var currentFocusKind: FocusKind { FocusKind.decode(shared.coreRuntime?.bridge?.currentFocusKind() ?? 0) }
    static var currentWorkoutKind: WorkoutKind { WorkoutKind.decode(shared.coreRuntime?.bridge?.currentWorkoutKind() ?? 0) }

    static func pushWorkoutEvent(_ event: WorkoutEvent) {
        shared.coreRuntime?.bridge?.pushWorkoutEvent(
            startMs: Int64(event.startTime.timeIntervalSince1970 * 1_000),
            endMs: Int64(event.endTime.timeIntervalSince1970 * 1_000),
            kind: event.kind.rawValue,
            vendorStrain: event.strainForRuntime,
            vendorRecovery: event.recoveryForRuntime
        )
    }

    static var personalizationContextJson: String? {
        shared.coreRuntime?.bridge?.personalizationContextJson()
    }

    // MARK: - Pipeline and vendor stream

    static func ensurePipeline() { shared.coreRuntime?.bridge?.ensurePipeline() }

    static func tick(at date: Date = Date()) -> String? {
        shared.coreRuntime?.bridge?.tick(timestampMs: Int64(date.timeIntervalSince1970 * 1_000))
    }

    static var lastRuntimeFeatures: [String: Any]? {
        shared.coreRuntime?.bridge?.lastFeatures()
    }

    @discardableResult
    static func startVendorStream(_ config: VendorStreamConfig) -> Int32 {
        guard let json = config.jsonString() else { return -1 }
        shared.installVendorStreamCallback(appId: config.appId, userId: config.userId)
        return shared.coreRuntime?.bridge?.startVendorStream(configJson: json) ?? -1
    }

    @discardableResult
    static func stopVendorStream() -> Int32 {
        let result = shared.coreRuntime?.bridge?.stopVendorStream() ?? -1
        shared.coreRuntime?.bridge?.clearStreamCallback()
        return result
    }

    static var vendorStreamState: [String: Any]? {
        shared.coreRuntime?.bridge?.vendorStreamState()
    }

    // MARK: - Syni cloud service

    static var syniService: SyniServiceClient? {
        if let existing = shared.syniServiceClient { return existing }
        guard let bridge = shared.coreRuntime?.bridge, bridge.isSyniServiceAvailable else { return nil }
        let client = SyniServiceClient(bridge: bridge)
        shared.syniServiceClient = client
        return client
    }

    private static func throwRuntimeMapError(_ map: [String: Any]) throws {
        if let error = map["error"] as? String, !error.isEmpty {
            throw SynheartError.runtimeOperationFailed(error)
        }
    }
}
