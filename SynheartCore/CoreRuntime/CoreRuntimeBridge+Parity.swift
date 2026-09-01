import Foundation

private enum ParityRuntimeSymbols {
    typealias HandleJson = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    typealias HandleStringJson = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias HandleTwoStringJson = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias HandleStringIntJson = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, Int32
    ) -> UnsafeMutablePointer<CChar>?
    typealias HandleTwoInt64Json = @convention(c) (
        OpaquePointer?, Int64, Int64
    ) -> UnsafeMutablePointer<CChar>?
    typealias HandleInt32Json = @convention(c) (OpaquePointer?, Int32) -> UnsafeMutablePointer<CChar>?
    typealias HandleInt64Int64Json = @convention(c) (
        OpaquePointer?, Int64, Int64
    ) -> UnsafeMutablePointer<CChar>?
    typealias HandleInt64 = @convention(c) (OpaquePointer?) -> Int64
    typealias HandleInt32 = @convention(c) (OpaquePointer?) -> Int32
    typealias HandleStringInt32 = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias HandleStringInt64 = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int64
    typealias HandleUInt8Int32 = @convention(c) (OpaquePointer?, UInt8) -> Int32
    typealias HandleInt64Json = @convention(c) (OpaquePointer?, Int64) -> UnsafeMutablePointer<CChar>?
    typealias HandleVoid = @convention(c) (OpaquePointer?) -> Void
    typealias GlobalStringInt32 = @convention(c) (UnsafePointer<CChar>?) -> Int32
    typealias GlobalJson = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias GlobalUInt64 = @convention(c) () -> UInt64
    typealias GlobalInt32 = @convention(c) () -> Int32

    typealias SyncJoin = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    typealias SyncRecover = SyncJoin

    typealias RequestDataDeletion = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Bool
    ) -> UnsafeMutablePointer<CChar>?
    typealias ListDataDeletions = @convention(c) (
        OpaquePointer?, Int32, Int32
    ) -> UnsafeMutablePointer<CChar>?

    typealias PushRrBatch = @convention(c) (
        OpaquePointer?, Int64, UnsafePointer<Double>?, Int, Int32, UnsafePointer<CChar>?
    ) -> Void
    typealias PushVendorHrv = @convention(c) (
        OpaquePointer?, Int64, Double, Double, Double, Double
    ) -> Void
    typealias PushVendorVitals = @convention(c) (
        OpaquePointer?, Int64, Double, Double
    ) -> Void
    typealias SetKind = @convention(c) (OpaquePointer?, Int32) -> Void
    typealias GetKind = @convention(c) (OpaquePointer?) -> Int32
    typealias PushWorkout = @convention(c) (
        OpaquePointer?, Int64, Int64, Int32, Double, Double
    ) -> Void

    static let syncCreateSpace: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_create_space")
    static let syncGeneratePairing: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_generate_pairing")
    static let syncJoinSpace: SyncJoin? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_join_space")
    static let syncReadiness: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_readiness")
    static let syncRecoverSpace: SyncRecover? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_recover_space")
    static let syncLeaveSpace: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_leave_space")
    static let syncListDevices: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_list_devices")
    static let syncRevokeDevice: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_revoke_device")
    static let syncDeleteSpace: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_delete_space")
    static let syncClearLocalSpace: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sync_clear_local_space")

    static let baselineHydrateLocal: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_baseline_hydrate_local")
    static let baselineExportOffline: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_baseline_export_offline")
    static let baselineImportOffline: HandleTwoStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_baseline_import_offline")

    static let sleepScore: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_sleep_score_compute_json")
    static let recoveryScore: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_recovery_score_compute_json")
    static let readinessScore: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_readiness_score_compute_json")
    static let attachSleepScore: HandleStringInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_attach_sleep_score_json")
    static let attachRecoveryScore: HandleUInt8Int32? = CoreRuntimeBridge.lookupSymbol("synheart_core_attach_recovery_score_today")
    static let clearRecoveryScore: HandleInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_clear_recovery_score_today")
    static let lastSleepScore: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_last_sleep_score_json")
    static let exportLongitudinal: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_export_longitudinal_snapshot")
    static let loadLongitudinal: HandleStringInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_load_longitudinal_snapshot")

    static let requestDataDeletion: RequestDataDeletion? = CoreRuntimeBridge.lookupSymbol("synheart_core_request_data_deletion")
    static let getDataDeletion: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_get_data_deletion")
    static let listDataDeletions: ListDataDeletions? = CoreRuntimeBridge.lookupSymbol("synheart_core_list_data_deletions")
    static let researchStudyStatus: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_research_study_status")
    static let recordStudyConsent: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_record_study_consent")

    static let pushRrBatch: PushRrBatch? = CoreRuntimeBridge.lookupSymbol("synheart_core_push_rr_batch")
    static let pushVendorHrv: PushVendorHrv? = CoreRuntimeBridge.lookupSymbol("synheart_core_push_vendor_hrv")
    static let pushVendorVitals: PushVendorVitals? = CoreRuntimeBridge.lookupSymbol("synheart_core_push_vendor_vitals")
    static let ingestVendorEvent: HandleStringInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_ingest_vendor_event")
    static let queryVendorEvents: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_query_vendor_events")
    static let latestVendorEvent: HandleTwoStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_get_latest_vendor_event")
    static let deleteVendorEvents: HandleStringInt64? = CoreRuntimeBridge.lookupSymbol("synheart_core_delete_vendor_events_for_provider")

    static let hsiHistoryList: HandleInt64Int64Json? = CoreRuntimeBridge.lookupSymbol("synheart_core_hsi_history_list")
    static let fetchCloudHsi: HandleTwoInt64Json? = CoreRuntimeBridge.lookupSymbol("synheart_core_fetch_cloud_hsi")
    static let hsiHistoryCount: HandleInt64? = CoreRuntimeBridge.lookupSymbol("synheart_core_hsi_history_count")
    static let hsiHistoryClear: HandleInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_hsi_history_clear")

    static let setTaskType: SetKind? = CoreRuntimeBridge.lookupSymbol("synheart_core_set_task_type")
    static let currentTaskType: GetKind? = CoreRuntimeBridge.lookupSymbol("synheart_core_current_task_type")
    static let setFocusKind: SetKind? = CoreRuntimeBridge.lookupSymbol("synheart_core_set_focus_kind")
    static let currentFocusKind: GetKind? = CoreRuntimeBridge.lookupSymbol("synheart_core_current_focus_kind")
    static let currentWorkoutKind: GetKind? = CoreRuntimeBridge.lookupSymbol("synheart_core_current_workout_kind")
    static let pushWorkoutEvent: PushWorkout? = CoreRuntimeBridge.lookupSymbol("synheart_core_push_workout_event")
    static let personalizationContext: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_personalization_context_json")

    static let syniChat: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_syni_chat")
    static let syniListSessions: HandleInt32Json? = CoreRuntimeBridge.lookupSymbol("synheart_core_syni_list_sessions")
    static let syniGetSession: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_syni_get_session")
    static let syniGetSessionMessages: HandleStringIntJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_syni_get_session_messages")
    static let syniCloseSession: HandleStringJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_syni_close_session")

    static let ensurePipeline: HandleVoid? = CoreRuntimeBridge.lookupSymbol("synheart_core_ensure_pipeline")
    static let tick: HandleInt64Json? = CoreRuntimeBridge.lookupSymbol("synheart_core_tick")
    static let lastFeatures: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_last_features")

    static let initLoggingBuffered: GlobalStringInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_init_logging_buffered")
    static let drainLogs: GlobalJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_drain_logs")
    static let droppedLogLines: GlobalUInt64? = CoreRuntimeBridge.lookupSymbol("synheart_core_dropped_log_lines")
    static let shutdownLogging: GlobalInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_shutdown_logging")

    static let streamStart: HandleStringInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_stream_start")
    static let streamStop: HandleInt32? = CoreRuntimeBridge.lookupSymbol("synheart_core_stream_stop")
    static let streamState: HandleJson? = CoreRuntimeBridge.lookupSymbol("synheart_core_stream_state")
}

extension CoreRuntimeBridge {
    private func json(_ pointer: UnsafeMutablePointer<CChar>?) -> [String: Any]? {
        guard let raw = consumeCString(pointer),
              let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func jsonArray(_ pointer: UnsafeMutablePointer<CChar>?) -> [[String: Any]] {
        guard let raw = consumeCString(pointer),
              let data = raw.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return values
    }

    /// Unwraps the runtime's sync envelope while preserving legacy bare maps.
    /// Failure envelopes remain inspectable through a stable string `error`
    /// plus the native fields supplied by the runtime.
    static func unwrapSyncEnvelope(_ raw: [String: Any]?) -> [String: Any]? {
        guard let raw else { return nil }
        guard raw.keys.contains("ok") else { return raw }
        if raw["ok"] as? Bool == true {
            return raw["data"] as? [String: Any] ?? [:]
        }
        guard let nativeError = raw["error"] as? [String: Any] else {
            return ["error": "UNKNOWN"]
        }
        var result = nativeError
        result["error"] = nativeError["message"] as? String
            ?? nativeError["code"] as? String
            ?? "UNKNOWN"
        return result
    }

    private func syncJson(_ pointer: UnsafeMutablePointer<CChar>?) -> [String: Any]? {
        Self.unwrapSyncEnvelope(json(pointer))
    }

    func syncCreateSpace(deviceName: String = "") -> [String: Any]? {
        deviceName.withCString { syncJson(ParityRuntimeSymbols.syncCreateSpace?(runtimeHandle, $0)) }
    }

    func syncGeneratePairing() -> [String: Any]? {
        syncJson(ParityRuntimeSymbols.syncGeneratePairing?(runtimeHandle))
    }

    func syncJoinSpace(pairingToken: String, deviceName: String = "") -> [String: Any]? {
        pairingToken.withCString { token in
            deviceName.withCString { name in
                syncJson(ParityRuntimeSymbols.syncJoinSpace?(runtimeHandle, token, name))
            }
        }
    }

    func syncReadiness() -> [String: Any]? {
        syncJson(ParityRuntimeSymbols.syncReadiness?(runtimeHandle))
    }

    func syncRecoverSpace(recoveryKey: String, spaceId: String) -> [String: Any]? {
        recoveryKey.withCString { key in
            spaceId.withCString { space in
                syncJson(ParityRuntimeSymbols.syncRecoverSpace?(runtimeHandle, key, space))
            }
        }
    }

    func syncLeaveSpace() -> [String: Any]? { syncJson(ParityRuntimeSymbols.syncLeaveSpace?(runtimeHandle)) }
    func syncListDevices() -> [String: Any]? { syncJson(ParityRuntimeSymbols.syncListDevices?(runtimeHandle)) }

    func syncRevokeDevice(deviceId: String) -> [String: Any]? {
        deviceId.withCString { syncJson(ParityRuntimeSymbols.syncRevokeDevice?(runtimeHandle, $0)) }
    }

    func syncDeleteSpace() -> [String: Any]? { syncJson(ParityRuntimeSymbols.syncDeleteSpace?(runtimeHandle)) }
    func syncClearLocalSpace() -> [String: Any]? { syncJson(ParityRuntimeSymbols.syncClearLocalSpace?(runtimeHandle)) }

    func baselineHydrateLocal() -> [String: Any]? {
        json(ParityRuntimeSymbols.baselineHydrateLocal?(runtimeHandle))
    }

    func baselineExportOffline(passphrase: String) -> Data? {
        guard !passphrase.isEmpty else { return nil }
        return passphrase.withCString { pointer in
            guard let result = json(ParityRuntimeSymbols.baselineExportOffline?(runtimeHandle, pointer)),
                  result["error"] == nil,
                  let encoded = result["blob_b64"] as? String else { return nil }
            return Data(base64Encoded: encoded)
        }
    }

    func baselineImportOffline(passphrase: String, blob: Data) -> [String: Any]? {
        let encoded = blob.base64EncodedString()
        return passphrase.withCString { pass in
            encoded.withCString { bytes in
                json(ParityRuntimeSymbols.baselineImportOffline?(runtimeHandle, pass, bytes))
            }
        }
    }

    func computeSleepScore(inputJson: String) -> String? {
        inputJson.withCString { consumeCString(ParityRuntimeSymbols.sleepScore?(runtimeHandle, $0)) }
    }

    func computeRecoveryScore(inputJson: String) -> String? {
        inputJson.withCString { consumeCString(ParityRuntimeSymbols.recoveryScore?(runtimeHandle, $0)) }
    }

    func computeReadinessScore(inputJson: String) -> String? {
        inputJson.withCString { consumeCString(ParityRuntimeSymbols.readinessScore?(runtimeHandle, $0)) }
    }

    func attachSleepScore(resultJson: String) -> Int32 {
        resultJson.withCString { ParityRuntimeSymbols.attachSleepScore?(runtimeHandle, $0) ?? -1 }
    }

    func attachRecoveryScoreToday(_ score: Int) -> Int32 {
        let clamped = UInt8(max(0, min(100, score)))
        return ParityRuntimeSymbols.attachRecoveryScore?(runtimeHandle, clamped) ?? -1
    }

    func clearRecoveryScoreToday() -> Int32 {
        ParityRuntimeSymbols.clearRecoveryScore?(runtimeHandle) ?? -1
    }

    func lastSleepScore() -> [String: Any]? {
        json(ParityRuntimeSymbols.lastSleepScore?(runtimeHandle))
    }

    func exportLongitudinalSnapshot() -> String? {
        consumeCString(ParityRuntimeSymbols.exportLongitudinal?(runtimeHandle))
    }

    func loadLongitudinalSnapshot(_ snapshotJson: String) -> Int32 {
        snapshotJson.withCString { ParityRuntimeSymbols.loadLongitudinal?(runtimeHandle, $0) ?? -1 }
    }

    func requestDataDeletion(reason: String, contact: String, dryRun: Bool) -> [String: Any]? {
        reason.withCString { reasonPointer in
            contact.withCString { contactPointer in
                json(ParityRuntimeSymbols.requestDataDeletion?(
                    runtimeHandle, reasonPointer, contactPointer, dryRun
                ))
            }
        }
    }

    func getDataDeletion(requestId: String) -> [String: Any]? {
        requestId.withCString { json(ParityRuntimeSymbols.getDataDeletion?(runtimeHandle, $0)) }
    }

    func listDataDeletions(limit: Int32, offset: Int32) -> [String: Any]? {
        json(ParityRuntimeSymbols.listDataDeletions?(runtimeHandle, limit, offset))
    }

    func researchStudyStatus() -> [String: Any]? {
        json(ParityRuntimeSymbols.researchStudyStatus?(runtimeHandle))
    }

    func recordStudyConsent(payloadJson: String) -> [String: Any]? {
        payloadJson.withCString { json(ParityRuntimeSymbols.recordStudyConsent?(runtimeHandle, $0)) }
    }

    func pushRrBatch(
        anchorTimestampMs: Int64,
        intervalsMs: [Double],
        newestFirst: Bool = false,
        provider: String = "default_sensor"
    ) {
        guard !intervalsMs.isEmpty else { return }
        intervalsMs.withUnsafeBufferPointer { values in
            provider.withCString { providerPointer in
                ParityRuntimeSymbols.pushRrBatch?(
                    runtimeHandle,
                    anchorTimestampMs,
                    values.baseAddress,
                    values.count,
                    newestFirst ? 1 : 0,
                    providerPointer
                )
            }
        }
    }

    func pushVendorHrv(
        timestampMs: Int64,
        rmssd: Double = -1,
        sdnn: Double = -1,
        stress: Double = -1,
        recovery: Double = -1
    ) {
        ParityRuntimeSymbols.pushVendorHrv?(runtimeHandle, timestampMs, rmssd, sdnn, stress, recovery)
    }

    func pushVendorVitals(timestampMs: Int64, spo2: Double = -1, respiration: Double = -1) {
        ParityRuntimeSymbols.pushVendorVitals?(runtimeHandle, timestampMs, spo2, respiration)
    }

    func ingestVendorEvent(json eventJson: String) -> Bool {
        eventJson.withCString { ParityRuntimeSymbols.ingestVendorEvent?(runtimeHandle, $0) == 0 }
    }

    func queryVendorEvents(queryJson: String) -> [String: Any]? {
        queryJson.withCString { json(ParityRuntimeSymbols.queryVendorEvents?(runtimeHandle, $0)) }
    }

    func latestVendorEvent(provider: String, eventType: String) -> [String: Any]? {
        provider.withCString { providerPointer in
            eventType.withCString { typePointer in
                json(ParityRuntimeSymbols.latestVendorEvent?(runtimeHandle, providerPointer, typePointer))
            }
        }
    }

    func deleteVendorEvents(provider: String) -> Int64 {
        provider.withCString { ParityRuntimeSymbols.deleteVendorEvents?(runtimeHandle, $0) ?? -1 }
    }

    func hsiHistory(sinceMs: Int64 = 0, limit: Int64 = 0) -> [[String: Any]] {
        jsonArray(ParityRuntimeSymbols.hsiHistoryList?(runtimeHandle, sinceMs, limit))
    }

    func fetchCloudHsi(fromMs: Int64, toMs: Int64) -> [[String: Any]] {
        jsonArray(ParityRuntimeSymbols.fetchCloudHsi?(runtimeHandle, fromMs, toMs))
    }

    func hsiHistoryCount() -> Int64 {
        max(0, ParityRuntimeSymbols.hsiHistoryCount?(runtimeHandle) ?? 0)
    }

    func clearHsiHistory() -> Bool {
        ParityRuntimeSymbols.hsiHistoryClear?(runtimeHandle) == 0
    }

    func setTaskType(_ value: Int32) { ParityRuntimeSymbols.setTaskType?(runtimeHandle, value) }
    func currentTaskType() -> Int32 { ParityRuntimeSymbols.currentTaskType?(runtimeHandle) ?? 0 }
    func setFocusKind(_ value: Int32) { ParityRuntimeSymbols.setFocusKind?(runtimeHandle, value) }
    func currentFocusKind() -> Int32 { ParityRuntimeSymbols.currentFocusKind?(runtimeHandle) ?? 0 }
    func currentWorkoutKind() -> Int32 { ParityRuntimeSymbols.currentWorkoutKind?(runtimeHandle) ?? 0 }

    func pushWorkoutEvent(
        startMs: Int64,
        endMs: Int64,
        kind: Int32,
        vendorStrain: Double,
        vendorRecovery: Double
    ) {
        ParityRuntimeSymbols.pushWorkoutEvent?(
            runtimeHandle, startMs, endMs, kind, vendorStrain, vendorRecovery
        )
    }

    func personalizationContextJson() -> String? {
        consumeCString(ParityRuntimeSymbols.personalizationContext?(runtimeHandle))
    }

    var isSyniServiceAvailable: Bool {
        ParityRuntimeSymbols.syniChat != nil
            && ParityRuntimeSymbols.syniListSessions != nil
            && ParityRuntimeSymbols.syniGetSession != nil
            && ParityRuntimeSymbols.syniGetSessionMessages != nil
            && ParityRuntimeSymbols.syniCloseSession != nil
    }

    func syniChat(requestJson: String) -> [String: Any]? {
        requestJson.withCString { json(ParityRuntimeSymbols.syniChat?(runtimeHandle, $0)) }
    }

    func syniListSessions(limit: Int32 = 0) -> [String: Any]? {
        json(ParityRuntimeSymbols.syniListSessions?(runtimeHandle, limit))
    }

    func syniGetSession(sessionId: String) -> [String: Any]? {
        sessionId.withCString { json(ParityRuntimeSymbols.syniGetSession?(runtimeHandle, $0)) }
    }

    func syniGetSessionMessages(sessionId: String, limit: Int32 = 0) -> [String: Any]? {
        sessionId.withCString {
            json(ParityRuntimeSymbols.syniGetSessionMessages?(runtimeHandle, $0, limit))
        }
    }

    func syniCloseSession(sessionId: String) -> [String: Any]? {
        sessionId.withCString { json(ParityRuntimeSymbols.syniCloseSession?(runtimeHandle, $0)) }
    }

    func ensurePipeline() { ParityRuntimeSymbols.ensurePipeline?(runtimeHandle) }

    func tick(timestampMs: Int64) -> String? {
        consumeCString(ParityRuntimeSymbols.tick?(runtimeHandle, timestampMs))
    }

    func lastFeatures() -> [String: Any]? {
        json(ParityRuntimeSymbols.lastFeatures?(runtimeHandle))
    }

    static func initializeBufferedLogging(configJson: String) -> Int32 {
        configJson.withCString { ParityRuntimeSymbols.initLoggingBuffered?($0) ?? -1 }
    }

    static func drainRuntimeLogs() -> String? {
        guard let pointer = ParityRuntimeSymbols.drainLogs?() else { return nil }
        let value = String(cString: pointer)
        // The runtime owns logging buffers; drained strings use the standard
        // runtime allocator and are released by its free-string entrypoint.
        if let free: (@convention(c) (UnsafeMutablePointer<CChar>?) -> Void) = lookupSymbol("synheart_core_free_string") {
            free(pointer)
        }
        return value
    }

    static var droppedRuntimeLogLines: UInt64 {
        ParityRuntimeSymbols.droppedLogLines?() ?? 0
    }

    static func shutdownRuntimeLogging() -> Int32 {
        ParityRuntimeSymbols.shutdownLogging?() ?? -1
    }

    func startVendorStream(configJson: String) -> Int32 {
        configJson.withCString { ParityRuntimeSymbols.streamStart?(runtimeHandle, $0) ?? -1 }
    }

    func stopVendorStream() -> Int32 {
        ParityRuntimeSymbols.streamStop?(runtimeHandle) ?? -1
    }

    func vendorStreamState() -> [String: Any]? {
        json(ParityRuntimeSymbols.streamState?(runtimeHandle))
    }
}
