import Foundation

/// Bridge to `libsynheart_core_runtime` via C ABI / dlsym.
///
/// This replaces the Swift-native storage, crypto, sync, consent, and pipeline
/// modules with a single native shared library that manages all of those concerns.
///
/// Library loading:
/// - macOS: `dlopen("libsynheart_core_runtime.dylib")`
/// - Linux: `dlopen("libsynheart_core_runtime.so")`
/// - iOS:   `RTLD_DEFAULT` (statically linked into the app binary)
///
/// All 42 `synheart_core_*` C symbols are resolved at load time.
/// Complex types are exchanged as JSON strings; all returned C strings
/// must be freed with `synheart_core_free_string`.
public final class CoreRuntimeBridge {

    // MARK: - Opaque handle

    private var handle: OpaquePointer

    // MARK: - C function type aliases (42 functions)

    // Lifecycle
    private typealias NewFn               = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias FreeFn              = @convention(c) (OpaquePointer?) -> Void
    private typealias FreeStringFn        = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    // Session
    private typealias StartSessionFn      = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias StopSessionFn       = @convention(c) (OpaquePointer?) -> Int32
    private typealias CurrentSessionFn    = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias IsRunningFn         = @convention(c) (OpaquePointer?) -> Int32

    // Sensor push
    private typealias PushRrFn            = @convention(c) (OpaquePointer?, Int64, Double) -> Void
    private typealias PushHrFn            = @convention(c) (OpaquePointer?, Int64, Double) -> Void
    private typealias PushAccelFn         = @convention(c) (OpaquePointer?, Int64, Double, Double, Double) -> Void
    private typealias PushBehaviorFn      = @convention(c) (OpaquePointer?, Int64, Int32, Double) -> Void
    private typealias PushSleepStagesFn   = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void
    private typealias IngestBatchFn       = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> UnsafeMutablePointer<CChar>?

    // Consent
    private typealias GrantConsentFn      = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias RevokeConsentFn     = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias HasConsentFn        = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias CurrentConsentFn    = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // Capabilities
    private typealias LoadCapTokenFn      = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32

    // Queries
    private typealias ListSessionsFn      = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias GetSummaryFn        = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias GetHsiWindowsFn     = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64, Int64, Int32) -> UnsafeMutablePointer<CChar>?
    private typealias GetStorageUsageFn   = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // Metrics
    private typealias RecordMetricFn      = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32

    // Deletion
    private typealias DeleteSessionFn     = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias WipeLocalDataFn     = @convention(c) (OpaquePointer?) -> Int32
    private typealias SetRetentionDaysFn  = @convention(c) (OpaquePointer?, Int32) -> Int64

    // Sync
    private typealias SetSyncEnabledFn    = @convention(c) (OpaquePointer?, Int32) -> Void
    private typealias SyncNowFn           = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // SRM / Baselines
    private typealias BaselinesJsonFn     = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias ExportSrmFn         = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias LoadSrmFn           = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias SrmOverallFn        = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // Cloud
    private typealias EnqueueHsiFn        = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> Void
    private typealias UploadQueueLenFn    = @convention(c) (OpaquePointer?) -> Int32
    private typealias FlushUploadsFn      = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias UploadMetadataFn    = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // Diagnostics
    private typealias DiagnosticsFn       = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias LastErrorCodeFn     = @convention(c) (OpaquePointer?) -> Int32
    private typealias IsRtAvailFn         = @convention(c) (OpaquePointer?) -> Int32
    private typealias IsNetReachFn        = @convention(c) (OpaquePointer?) -> Int32

    // Account deletion
    private typealias ReqAcctDelFn        = @convention(c) (OpaquePointer?) -> Int32
    private typealias CancelAcctDelFn     = @convention(c) (OpaquePointer?) -> Int32

    // Wearable SRM (longitudinal)
    private typealias PushWearDailyFn     = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, Double, Double, Int32) -> Void
    private typealias TriggerWearRecompFn = @convention(c) (OpaquePointer?, Int32, Int32) -> Void
    private typealias GetWearRefFn        = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // Ambient capture
    private typealias SetAmbientCaptureFn = @convention(c) (OpaquePointer?, Int32) -> Void
    private typealias GetAmbientCaptureFn = @convention(c) (OpaquePointer?) -> Int32

    // MARK: - Resolved function pointers (42)

    private static let lib: UnsafeMutableRawPointer? = {
        #if os(macOS)
        if let h = dlopen("libsynheart_core_runtime.dylib", RTLD_LAZY) { return h }
        #elseif os(Linux)
        if let h = dlopen("libsynheart_core_runtime.so", RTLD_LAZY) { return h }
        #endif
        // iOS: library is statically linked; use RTLD_DEFAULT
        return UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    }()

    private static func sym<T>(_ name: String) -> T? {
        guard let lib = lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    // Lifecycle
    private static let _new:           NewFn?             = sym("synheart_core_new")
    private static let _free:          FreeFn?            = sym("synheart_core_free")
    private static let _freeString:    FreeStringFn?      = sym("synheart_core_free_string")

    // Session
    private static let _startSession:  StartSessionFn?    = sym("synheart_core_start_session")
    private static let _stopSession:   StopSessionFn?     = sym("synheart_core_stop_session")
    private static let _curSession:    CurrentSessionFn?   = sym("synheart_core_current_session")
    private static let _isRunning:     IsRunningFn?       = sym("synheart_core_is_running")

    // Sensor push
    private static let _pushRr:        PushRrFn?          = sym("synheart_core_push_rr")
    private static let _pushHr:        PushHrFn?          = sym("synheart_core_push_hr")
    private static let _pushAccel:     PushAccelFn?       = sym("synheart_core_push_accel")
    private static let _pushBehavior:  PushBehaviorFn?    = sym("synheart_core_push_behavior")
    private static let _pushSleep:     PushSleepStagesFn? = sym("synheart_core_push_sleep_stages")
    private static let _ingestBatch:   IngestBatchFn?     = sym("synheart_core_ingest_batch")

    // Ambient capture
    private static let _setAmbient:    SetAmbientCaptureFn? = sym("synheart_core_set_ambient_capture")
    private static let _getAmbient:    GetAmbientCaptureFn? = sym("synheart_core_get_ambient_capture")

    // Consent
    private static let _grantConsent:  GrantConsentFn?    = sym("synheart_core_grant_consent")
    private static let _revokeConsent: RevokeConsentFn?   = sym("synheart_core_revoke_consent")
    private static let _hasConsent:    HasConsentFn?      = sym("synheart_core_has_consent")
    private static let _curConsent:    CurrentConsentFn?   = sym("synheart_core_current_consent")

    // Capabilities
    private static let _loadCapToken:  LoadCapTokenFn?    = sym("synheart_core_load_capability_token")

    // Queries
    private static let _listSessions:  ListSessionsFn?    = sym("synheart_core_list_sessions")
    private static let _getSummary:    GetSummaryFn?      = sym("synheart_core_get_session_summary")
    private static let _getHsiWin:     GetHsiWindowsFn?   = sym("synheart_core_get_hsi_windows")
    private static let _getStorUse:    GetStorageUsageFn?  = sym("synheart_core_get_storage_usage")

    // Metrics
    private static let _recordMetric:  RecordMetricFn?    = sym("synheart_core_record_metric")

    // Deletion
    private static let _deleteSession: DeleteSessionFn?   = sym("synheart_core_delete_session")
    private static let _wipeLocal:     WipeLocalDataFn?   = sym("synheart_core_wipe_local_data")
    private static let _setRetention:  SetRetentionDaysFn? = sym("synheart_core_set_retention_days")

    // Sync
    private static let _setSyncOn:     SetSyncEnabledFn?  = sym("synheart_core_set_sync_enabled")
    private static let _syncNow:       SyncNowFn?         = sym("synheart_core_sync_now")

    // SRM / Baselines
    private static let _baselines:     BaselinesJsonFn?   = sym("synheart_core_baselines_json")
    private static let _exportSrm:     ExportSrmFn?       = sym("synheart_core_export_srm_snapshot")
    private static let _loadSrm:       LoadSrmFn?         = sym("synheart_core_load_srm_snapshot")
    private static let _srmStatus:     SrmOverallFn?      = sym("synheart_core_srm_overall_status")

    // Cloud
    private static let _enqueueHsi:    EnqueueHsiFn?      = sym("synheart_core_enqueue_hsi")
    private static let _uploadQLen:    UploadQueueLenFn?  = sym("synheart_core_upload_queue_length")
    private static let _flushUploads:  FlushUploadsFn?    = sym("synheart_core_flush_uploads")
    private static let _uploadMeta:    UploadMetadataFn?  = sym("synheart_core_upload_metadata")

    // Wellness Score
    private static let _wellnessJson:  DiagnosticsFn?     = sym("synheart_core_wellness_json")

    // Diagnostics
    private static let _diagnostics:   DiagnosticsFn?     = sym("synheart_core_diagnostics")
    private static let _lastErrCode:   LastErrorCodeFn?   = sym("synheart_core_last_error_code")
    private static let _isRtAvail:     IsRtAvailFn?       = sym("synheart_core_is_runtime_available")
    private static let _isNetReach:    IsNetReachFn?      = sym("synheart_core_is_network_reachable")

    // Account deletion
    private static let _reqAcctDel:    ReqAcctDelFn?      = sym("synheart_core_request_account_deletion")
    private static let _cancelAcctDel: CancelAcctDelFn?   = sym("synheart_core_cancel_account_deletion")

    // Wearable SRM (longitudinal)
    private static let _pushWearDaily: PushWearDailyFn?     = sym("synheart_core_push_wearable_daily_value")
    private static let _triggerWearRe: TriggerWearRecompFn? = sym("synheart_core_trigger_wearable_recompute")
    private static let _getWearRef:    GetWearRefFn?        = sym("synheart_core_get_wearable_reference")

    // MARK: - Availability check

    /// Whether the core runtime library is linked and the `synheart_core_new` symbol is resolved.
    public static var isAvailable: Bool {
        _new != nil
    }

    // MARK: - Init / Deinit

    /// Create a new CoreRuntimeBridge from a JSON config string.
    ///
    /// Returns nil if the library is not linked or if configuration fails.
    ///
    /// Config JSON keys: `app_id`, `subject_id`, `mode` ("personal"|"insight"|"research"),
    /// `device_id`, `app_version`, `platform`, `storage`, `sync`, `privacy`,
    /// `capability_token`, `capability_secret`.
    public init?(configJson: String) {
        guard let newFn = Self._new else { return nil }
        guard let ptr = configJson.withCString({ newFn($0) }) else { return nil }
        self.handle = ptr
    }

    deinit {
        Self._free?(handle)
    }

    // MARK: - String Helpers

    /// Convert a C string pointer to a Swift String, freeing the C string afterward.
    /// Returns nil if the pointer is null.
    private func consumeCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr = ptr else { return nil }
        let result = String(cString: ptr)
        Self._freeString?(ptr)
        return result
    }

    // MARK: - Session Lifecycle

    /// Start a new session. Returns session handle JSON, or nil on failure.
    ///
    /// JSON: `{ "session_id": "...", "started_at_ms": 123, "mode": "personal" }`
    public func startSession() -> String? {
        consumeCString(Self._startSession?(handle))
    }

    /// Stop the current session. Returns true on success.
    public func stopSession() -> Bool {
        (Self._stopSession?(handle) ?? 1) == 0
    }

    /// Get the current session as JSON, or nil if none.
    public func currentSession() -> String? {
        consumeCString(Self._curSession?(handle))
    }

    /// Whether a session is currently running.
    public func isRunning() -> Bool {
        (Self._isRunning?(handle) ?? 0) != 0
    }

    // MARK: - Sensor Push

    /// Push an RR-interval sample.
    public func pushRr(tsMs: Int64, rrMs: Double) {
        Self._pushRr?(handle, tsMs, rrMs)
    }

    /// Push a heart-rate sample.
    public func pushHr(tsMs: Int64, bpm: Double) {
        Self._pushHr?(handle, tsMs, bpm)
    }

    /// Push a tri-axis accelerometer sample.
    public func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double) {
        Self._pushAccel?(handle, tsMs, x, y, z)
    }

    /// Push a behavior event.
    public func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
        Self._pushBehavior?(handle, tsMs, eventType, value)
    }

    /// Push sleep stage data as JSON.
    public func pushSleepStages(json: String) {
        json.withCString { Self._pushSleep?(handle, $0) }
    }

    /// Batch ingest events JSON. Returns HSI JSON if a window completed, or nil.
    public func ingestBatch(batchJson: String, nowMs: Int64) -> String? {
        let ptr = batchJson.withCString { Self._ingestBatch?(handle, $0, nowMs) }
        return consumeCString(ptr)
    }

    // MARK: - Ambient Capture

    /// Enable/disable ambient capture mode (HSI windows forwarded
    /// regardless of session state).
    public func setAmbientCapture(_ enabled: Bool) {
        Self._setAmbient?(handle, enabled ? 1 : 0)
    }

    /// Read the ambient-capture flag.
    public func getAmbientCapture() -> Bool {
        return (Self._getAmbient?(handle) ?? 0) != 0
    }

    // MARK: - Consent

    /// Grant a consent type (e.g. "biosignals", "behavior", "phone_context",
    /// "cloud_upload", "focus_estimation", "emotion_estimation", "syni").
    /// Returns true on success.
    public func grantConsent(type: String) -> Bool {
        type.withCString { (Self._grantConsent?(handle, $0) ?? 1) == 0 }
    }

    /// Revoke a consent type. Returns true on success.
    public func revokeConsent(type: String) -> Bool {
        type.withCString { (Self._revokeConsent?(handle, $0) ?? 1) == 0 }
    }

    /// Check if a consent type is granted.
    public func hasConsent(type: String) -> Bool {
        type.withCString { (Self._hasConsent?(handle, $0) ?? 0) != 0 }
    }

    /// Get the full consent snapshot as JSON.
    public func currentConsent() -> String? {
        consumeCString(Self._curConsent?(handle))
    }

    // MARK: - Capabilities

    /// Load a capability token. Returns true on success.
    public func loadCapabilityToken(tokenJson: String, secret: String) -> Bool {
        tokenJson.withCString { tj in
            secret.withCString { sec in
                (Self._loadCapToken?(handle, tj, sec) ?? 1) == 0
            }
        }
    }

    // MARK: - Queries

    /// List sessions as a JSON array.
    public func listSessions() -> String? {
        consumeCString(Self._listSessions?(handle))
    }

    /// Get decrypted session summary JSON, or nil.
    public func getSessionSummary(sessionId: String) -> String? {
        let ptr = sessionId.withCString { Self._getSummary?(handle, $0) }
        return consumeCString(ptr)
    }

    /// Get decrypted HSI windows as JSON array.
    /// Pass 0 for startMs/endMs/limit to indicate "no filter".
    public func getHsiWindows(sessionId: String, startMs: Int64 = 0, endMs: Int64 = 0, limit: Int32 = 0) -> String? {
        let ptr = sessionId.withCString { Self._getHsiWin?(handle, $0, startMs, endMs, limit) }
        return consumeCString(ptr)
    }

    /// Get storage usage as JSON.
    public func getStorageUsage() -> String? {
        consumeCString(Self._getStorUse?(handle))
    }

    // MARK: - Metrics

    /// Record a metric event from JSON. Returns true on success.
    ///
    /// JSON: `{ "name": "...", "timestamp_ms": 123, "value": ..., "tags": {...} }`
    public func recordMetric(json: String) -> Bool {
        json.withCString { (Self._recordMetric?(handle, $0) ?? 1) == 0 }
    }

    // MARK: - Deletion

    /// Delete a session and create a tombstone. Returns true on success.
    public func deleteSession(sessionId: String) -> Bool {
        sessionId.withCString { (Self._deleteSession?(handle, $0) ?? 1) == 0 }
    }

    /// Wipe all local data. Returns true on success.
    public func wipeLocalData() -> Bool {
        (Self._wipeLocal?(handle) ?? 1) == 0
    }

    /// Set retention days. Returns number of deleted artifacts, or -1 on error.
    public func setRetentionDays(days: Int32) -> Int64 {
        Self._setRetention?(handle, days) ?? -1
    }

    // MARK: - Sync

    /// Enable or disable sync.
    public func setSyncEnabled(enabled: Bool) {
        Self._setSyncOn?(handle, enabled ? 1 : 0)
    }

    /// Run a sync cycle. Returns result JSON, or nil on error.
    ///
    /// JSON: `{ "pushed": N, "pulled": N, "errors": [...] }`
    public func syncNow() -> String? {
        consumeCString(Self._syncNow?(handle))
    }

    // MARK: - SRM / Baselines

    /// Get SRM baselines as JSON, or nil.
    public func baselinesJson() -> String? {
        consumeCString(Self._baselines?(handle))
    }

    /// Export SRM snapshot as JSON, or nil.
    public func exportSrmSnapshot() -> String? {
        consumeCString(Self._exportSrm?(handle))
    }

    /// Load SRM snapshot from JSON. Returns true on success.
    public func loadSrmSnapshot(json: String) -> Bool {
        json.withCString { (Self._loadSrm?(handle, $0) ?? 1) == 0 }
    }

    /// Get SRM overall baseline status as JSON.
    ///
    /// JSON: `{ "status": "empty|warming|ready" }`
    public func srmOverallStatus() -> String? {
        consumeCString(Self._srmStatus?(handle))
    }

    // MARK: - Cloud / Upload Queue

    /// Enqueue an HSI snapshot for background upload.
    public func enqueueHsi(json: String, timestampMs: Int64) {
        json.withCString { Self._enqueueHsi?(handle, $0, timestampMs) }
    }

    /// Get the number of items in the upload queue.
    public func uploadQueueLength() -> Int {
        Int(Self._uploadQLen?(handle) ?? 0)
    }

    /// Flush the upload queue. Blocks. Returns result JSON, or nil on error.
    ///
    /// JSON: `{ "uploaded": N, "failed": N, "requeued": N }`
    public func flushUploads() -> String? {
        consumeCString(Self._flushUploads?(handle))
    }

    /// Get upload metadata summary as JSON.
    public func uploadMetadata() -> String? {
        consumeCString(Self._uploadMeta?(handle))
    }

    // MARK: - Wellness Score

    /// Get the last Wellness Score as JSON, or nil if baselines are not ready.
    public func wellnessJson() -> String? {
        consumeCString(Self._wellnessJson?(handle))
    }

    // MARK: - Diagnostics

    /// Get runtime diagnostics as JSON, or nil.
    public func diagnostics() -> String? {
        consumeCString(Self._diagnostics?(handle))
    }

    /// Get the last runtime error code (0 = no error).
    public func lastErrorCode() -> Int {
        Int(Self._lastErrCode?(handle) ?? 0)
    }

    /// Whether the signal-processing runtime pipeline is available.
    public func isRuntimeAvailable() -> Bool {
        (Self._isRtAvail?(handle) ?? 0) != 0
    }

    /// Whether the network is reachable.
    public func isNetworkReachable() -> Bool {
        (Self._isNetReach?(handle) ?? 0) != 0
    }

    // MARK: - Account Deletion

    /// Request account deletion. Blocks. Returns true on success.
    public func requestAccountDeletion() -> Bool {
        (Self._reqAcctDel?(handle) ?? 1) == 0
    }

    /// Cancel account deletion. Blocks. Returns true on success.
    public func cancelAccountDeletion() -> Bool {
        (Self._cancelAcctDel?(handle) ?? 1) == 0
    }

    // MARK: - Wearable SRM (Longitudinal)

    /// Push a daily wearable dimension value for longitudinal SRM computation.
    public func pushWearableDailyValue(dimension: String, dayIndex: Int, value: Double, confidence: Double, fidelity: Int32) {
        dimension.withCString { Self._pushWearDaily?(handle, $0, Int32(dayIndex), value, confidence, fidelity) }
    }

    /// Trigger a wearable SRM recompute.
    public func triggerWearableRecompute(triggerType: Int32, asOfDay: Int) {
        Self._triggerWearRe?(handle, triggerType, Int32(asOfDay))
    }

    /// Get the current wearable reference JSON from the longitudinal SRM engine.
    public func getWearableReference() -> String? {
        consumeCString(Self._getWearRef?(handle))
    }

    // MARK: - Lab Protocol

    private typealias LabAvailFn         = @convention(c) (OpaquePointer?) -> Int32
    private typealias LabStartFn         = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> Int32
    private typealias LabOpenWindowFn    = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias LabCloseWindowFn   = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> Int32
    private typealias LabSetWindowValFn  = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias LabMergeExtraFn    = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    private typealias LabSetOverridesFn  = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias LabFinalizeFn      = @convention(c) (OpaquePointer?, Int64) -> UnsafeMutablePointer<CChar>?

    private static let _labAvail:        LabAvailFn?        = sym("synheart_core_lab_available")
    private static let _labStart:        LabStartFn?        = sym("synheart_core_lab_start")
    private static let _labOpenWin:      LabOpenWindowFn?   = sym("synheart_core_lab_open_window")
    private static let _labCloseWin:     LabCloseWindowFn?  = sym("synheart_core_lab_close_window")
    private static let _labSetWinVal:    LabSetWindowValFn? = sym("synheart_core_lab_set_window_values")
    private static let _labMergeExtra:   LabMergeExtraFn?   = sym("synheart_core_lab_merge_extra_data")
    private static let _labSetOverrides: LabSetOverridesFn? = sym("synheart_core_lab_set_state_overrides")
    private static let _labFinalize:     LabFinalizeFn?     = sym("synheart_core_lab_finalize")

    /// Whether the lab protocol engine is available in the linked runtime.
    public func isLabAvailable() -> Bool {
        (Self._labAvail?(handle) ?? 0) != 0
    }

    /// Start a lab protocol.
    /// - Parameters:
    ///   - protocolJson: JSON describing the protocol configuration.
    ///   - startedAtMs: epoch millis when the protocol started.
    /// - Returns: true on success.
    public func labStart(protocolJson: String, startedAtMs: Int64) -> Bool {
        protocolJson.withCString { (Self._labStart?(handle, $0, startedAtMs) ?? 1) == 0 }
    }

    /// Open a new window within a running lab protocol.
    /// - Returns: The window ID string, or nil on failure.
    public func labOpenWindow(parentId: String, windowType: String, label: String, startedAtMs: Int64) -> String? {
        let ptr = parentId.withCString { pid in
            windowType.withCString { wt in
                label.withCString { lb in
                    Self._labOpenWin?(handle, pid, wt, lb, startedAtMs)
                }
            }
        }
        return consumeCString(ptr)
    }

    /// Close an open lab window.
    /// - Returns: true on success.
    public func labCloseWindow(windowId: String, endedAtMs: Int64) -> Bool {
        windowId.withCString { (Self._labCloseWin?(handle, $0, endedAtMs) ?? 1) == 0 }
    }

    /// Set values on a lab window.
    /// - Returns: true on success.
    public func labSetWindowValues(windowId: String, valuesJson: String) -> Bool {
        windowId.withCString { wid in
            valuesJson.withCString { vj in
                (Self._labSetWinVal?(handle, wid, vj) ?? 1) == 0
            }
        }
    }

    /// Merge extra data into the running lab protocol.
    /// - Returns: true on success.
    public func labMergeExtraData(patchJson: String) -> Bool {
        patchJson.withCString { (Self._labMergeExtra?(handle, $0) ?? 1) == 0 }
    }

    /// Set state overrides on a lab window.
    /// - Returns: true on success.
    public func labSetStateOverrides(windowId: String, overridesJson: String) -> Bool {
        windowId.withCString { wid in
            overridesJson.withCString { oj in
                (Self._labSetOverrides?(handle, wid, oj) ?? 1) == 0
            }
        }
    }

    /// Finalize the lab protocol.
    /// - Returns: Result JSON string, or nil on failure.
    public func labFinalize(endedAtMs: Int64) -> String? {
        consumeCString(Self._labFinalize?(handle, endedAtMs))
    }

    // MARK: - Breathing (RFC-Breathing-001)

    // RR samples pushed via `pushRr` already feed the detector. These
    // configure the target / window / population and read back JSON
    // verdicts. JSON shape mirrors `synheart_breathing_runtime::ComplianceResult`.

    private typealias BreathSetTargetBpmFn  = @convention(c) (OpaquePointer?, Double) -> Void
    private typealias BreathSetWindowSecsFn = @convention(c) (OpaquePointer?, Int32)  -> Void
    private typealias BreathSetPopulationFn = @convention(c) (OpaquePointer?, Int32)  -> Void
    private typealias BreathEvaluateFn      = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias BreathResetFn         = @convention(c) (OpaquePointer?) -> Void

    private static let _breathSetTargetBpm:  BreathSetTargetBpmFn?  = sym("synheart_core_breathing_set_target_bpm")
    private static let _breathSetWindowSecs: BreathSetWindowSecsFn? = sym("synheart_core_breathing_set_window_secs")
    private static let _breathSetPopulation: BreathSetPopulationFn? = sym("synheart_core_breathing_set_population")
    private static let _breathEvaluate:      BreathEvaluateFn?      = sym("synheart_core_breathing_evaluate")
    private static let _breathReset:         BreathResetFn?         = sym("synheart_core_breathing_reset")

    /// Set the target breathing rate in breaths per minute (e.g. 6.0 for resonance).
    public func breathingSetTargetBpm(_ bpm: Double) {
        Self._breathSetTargetBpm?(handle, bpm)
    }

    /// Set the rolling-window length in seconds. Native side clamps to `[30, 120]`.
    public func breathingSetWindowSecs(_ secs: Int) {
        Self._breathSetWindowSecs?(handle, Int32(secs))
    }

    /// Set the population threshold profile.
    /// `0 = Beginner`, `1 = Experienced`, `2 = Clinical`.
    public func breathingSetPopulation(_ profile: Int) {
        Self._breathSetPopulation?(handle, Int32(profile))
    }

    /// Evaluate breathing compliance over the current RR window. Returns a
    /// JSON `ComplianceResult` string or nil when there isn't enough Tier-1
    /// data yet.
    public func breathingEvaluateJson() -> String? {
        return consumeCString(Self._breathEvaluate?(handle))
    }

    /// Clear the breathing detector's RR ring buffer.
    public func breathingReset() {
        Self._breathReset?(handle)
    }

    // MARK: - HSI State Callback

    private typealias SetHsiCallbackFn = @convention(c) (
        OpaquePointer?,
        @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void,
        UnsafeMutableRawPointer?
    ) -> Void
    private typealias ClearHsiCallbackFn = @convention(c) (OpaquePointer?) -> Void

    private static let _setHsiCb: SetHsiCallbackFn? = sym("synheart_core_set_hsi_callback")
    private static let _clearHsiCb: ClearHsiCallbackFn? = sym("synheart_core_clear_hsi_callback")

    /// Register a callback for real-time HSI state updates.
    ///
    /// The callback fires on a background thread. Dispatch to main thread
    /// if updating UI.
    public func setHsiCallback(_ callback: @escaping (String) -> Void) {
        // Store the closure in a box so we can pass it as user_data
        let box = Unmanaged.passRetained(callback as AnyObject)
        let ud = box.toOpaque()

        let cCallback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { jsonPtr, userData in
            guard let jsonPtr = jsonPtr, let userData = userData else { return }
            let json = String(cString: jsonPtr)
            let cb = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue() as! (String) -> Void
            cb(json)
        }

        Self._setHsiCb?(handle, cCallback, ud)
    }

    /// Unregister the HSI callback.
    public func clearHsiCallback() {
        Self._clearHsiCb?(handle)
    }
}
