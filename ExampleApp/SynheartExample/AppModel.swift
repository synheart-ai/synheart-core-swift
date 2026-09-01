import Combine
import Foundation
import SynheartCore

@MainActor
final class AppModel: ObservableObject {
    enum ConsentKind: String, CaseIterable, Identifiable {
        case biosignals, behavior, phoneContext, cloudUpload, syni, vendorSync, research

        var id: String { rawValue }
        var title: String {
            switch self {
            case .biosignals: return "Biosignals"
            case .behavior: return "Behavior"
            case .phoneContext: return "Phone context"
            case .cloudUpload: return "Cloud upload"
            case .syni: return "Syni personalization"
            case .vendorSync: return "Vendor sync"
            case .research: return "Research"
            }
        }

        static let collection: [ConsentKind] = [.biosignals, .behavior, .phoneContext]
        static let optionalSharing: [ConsentKind] = [.cloudUpload, .syni, .vendorSync, .research]
    }

    enum CloudIngestionStage: Equatable {
        case localOnly
        case needsInitialization
        case needsCloudConsent
        case needsDeviceRegistration
        case needsCloudAuthorization
        case needsCollectionConsent
        case readyToCollect
        case collecting
        case readyToUpload
        case uploadFailed
        case noArtifacts
        case verified

        var title: String {
            switch self {
            case .localOnly: return "Cloud ingestion is off"
            case .needsInitialization: return "Initialize the SDK"
            case .needsCloudConsent: return "Grant cloud consent"
            case .needsDeviceRegistration: return "Register this device"
            case .needsCloudAuthorization: return "Complete cloud authorization"
            case .needsCollectionConsent: return "Allow test data collection"
            case .readyToCollect: return "Create test data"
            case .collecting: return "Collection is running"
            case .readyToUpload: return "Artifacts are ready"
            case .uploadFailed: return "Last upload failed"
            case .noArtifacts: return "No artifacts were uploaded"
            case .verified: return "Ingestion successful"
            }
        }

        var guidance: String {
            switch self {
            case .localOnly:
                return "Add the cloud environment values to the app scheme, then rebuild and initialize the SDK."
            case .needsInitialization:
                return "The configured runtime must be initialized before device registration or ingestion."
            case .needsCloudConsent:
                return "Cloud upload is the trigger for device registration. Save that choice first; local collection remains available if registration fails."
            case .needsDeviceRegistration:
                return "Registration is pending or failed. Debug registration also requires development mode for this app ID on the server."
            case .needsCloudAuthorization:
                return "The choice is saved and the device is registered, but app policy or the consent profile has not issued an effective cloud grant yet."
            case .needsCollectionConsent:
                return "The guided test uses real behavior events. Grant Behavior consent to produce test data."
            case .readyToCollect:
                return "Start a session and interact through two processing windows. Behavior-derived HSI normally needs about 120 seconds."
            case .collecting:
                return "Keep interacting until HSI with data is greater than zero. The first delivery may be an empty window; behavior-derived axes normally arrive in the following window."
            case .readyToUpload:
                return "The native runtime has finalized and queued artifacts. Flush the queue to test real cloud ingestion."
            case .uploadFailed:
                return "Review the failure below, then retry. Retryable data remains in the native queue."
            case .noArtifacts:
                return "The flush reached the runtime but had nothing to upload. Run a longer session before trying again."
            case .verified:
                return "Synheart Cloud accepted the finalized artifact. The end-to-end ingestion test is complete."
            }
        }

        var actionTitle: String? {
            switch self {
            case .localOnly: return nil
            case .needsInitialization: return "Initialize SDK"
            case .needsCloudConsent: return "Grant Cloud Consent"
            case .needsDeviceRegistration: return "Register Device"
            case .needsCloudAuthorization: return "Retry Cloud Authorization"
            case .needsCollectionConsent: return "Grant Behavior Consent"
            case .readyToCollect: return "Start Collection Session"
            case .collecting: return "Stop & Finalize Session"
            case .readyToUpload: return "Flush Upload Queue"
            case .uploadFailed: return "Retry Upload"
            case .noArtifacts: return "Start Another Session"
            case .verified: return "Run Another Test"
            }
        }
    }

    @Published var appId: String
    @Published var subjectId: String
    @Published var allowUnsignedCapabilities: Bool
    @Published private(set) var deviceId: String
    @Published private(set) var isInitialized = false
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var activeOperation: String?
    @Published private(set) var startActionPhase = "idle"
    @Published private(set) var stopActionPhase = "idle"
    @Published private(set) var requestedConsent: ConsentForm
    @Published private(set) var isSavingConsent = false
    @Published private(set) var effectiveConsent: ConsentEffectiveState?
    @Published private(set) var currentSession: SessionHandle?
    @Published private(set) var collectionStartupFailures: [String: String] = [:]
    @Published private(set) var latestState: HSIState?
    @Published private(set) var rawHSI = ""
    @Published private(set) var rawFrameCount = 0
    @Published private(set) var typedStateCount = 0
    @Published private(set) var dataBearingStateCount = 0
    @Published private(set) var behaviorEventCount = 0
    @Published private(set) var behaviorEventBreakdown: [String: Int] = [:]
    @Published private(set) var motionSampleCount = 0
    @Published private(set) var wearSampleCount = 0
    @Published private(set) var wearDataSampleCount = 0
    @Published private(set) var lastWearSample: WearSample?
    @Published private(set) var storageUsage: StorageUsage?
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var uploadStatus = UploadQueueStatus(state: .localOnly, queueLength: 0)
    @Published private(set) var lastFlushResult: UploadFlushResult?
    @Published private(set) var deviceAuthStatus: DeviceAuthStatus?
    @Published private(set) var lastRegistrationFailure: NativeOperationFailure?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSuccess: String?
    @Published private(set) var events: [String] = []

    let symbolDiagnostics = CoreRuntimeBridge.symbolDiagnostics
    let dependencyDiagnostics = CoreRuntimeBridge.dependencyDiagnostics
    let environment = ExampleEnvironment.current

    private var subscriptions = Set<AnyCancellable>()
    private var statusTimer: AnyCancellable?
    private let defaults = UserDefaults.standard
    private var cloudTestBaselineUploadAt: Date?
    private var cloudTestHasFinalizedSession = false
    private var automatedProbeHasRun = false
    private var automatedProbeTimeline: [[String: Any]] = []
    private var confirmedRequestedConsent: ConsentForm
    private var consentSaveWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let defaults = UserDefaults.standard
        let parityProbe = CommandLine.arguments.contains("--run-parity-probe")
        let storedSubject = parityProbe
            ? "parity_\(UUID().uuidString.lowercased())"
            : defaults.string(forKey: "example.subjectId")
                ?? "example_\(UUID().uuidString.lowercased())"
        let storedDevice = defaults.string(forKey: "example.deviceId")
            ?? UUID().uuidString.lowercased()
        if !parityProbe {
            defaults.set(storedSubject, forKey: "example.subjectId")
        }
        defaults.set(storedDevice, forKey: "example.deviceId")

        appId = ExampleEnvironment.current.appId
            ?? defaults.string(forKey: "example.appId")
            ?? Bundle.main.bundleIdentifier
            ?? "ai.synheart.core.example"
        subjectId = storedSubject
        deviceId = storedDevice
        let initialConsent = ConsentForm(
            profileId: "example-local",
            biosignals: false,
            phoneContext: false,
            behavior: false,
            consentTier: .local,
            allowCloud: false,
            allowResearch: false,
            allowVendorSync: false
        )
        requestedConsent = initialConsent
        confirmedRequestedConsent = initialConsent
#if DEBUG
        allowUnsignedCapabilities = true
#else
        allowUnsignedCapabilities = false
#endif
    }

    var isDeviceAuthConfigured: Bool {
        environment.authBaseUrl != nil || environment.cloudBaseUrl != nil
    }

    var isCloudConfigured: Bool {
        environment.cloudBaseUrl != nil
            && environment.orgId != nil
            && isDeviceAuthConfigured
    }

    var configuredPackageName: String {
        environment.packageName ?? Bundle.main.bundleIdentifier ?? ""
    }

    var allowsUnattestedDevRegistration: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    var cloudFailure: NativeOperationFailure? {
        lastRegistrationFailure ?? uploadStatus.lastFailure ?? lastFlushResult?.failure
    }

    var modeDescription: String { isCloudConfigured ? "Cloud test" : "Local only" }

    var hasCollectionConsent: Bool {
        guard let effectiveConsent else { return false }
        return effectiveConsent.biosignals || effectiveConsent.behavior || effectiveConsent.phoneContext
    }

    var hasBehaviorConsent: Bool {
        effectiveConsent?.behavior == true
    }

    var canStartSession: Bool {
        isInitialized && !isRunning && hasCollectionConsent && !isBusy && !isSavingConsent
    }

    var isStoppingSession: Bool { activeOperation == "Stop session" }

    var operationStateDescription: String {
        activeOperation
            ?? (isSavingConsent ? "Update data permissions" : nil)
            ?? (isBusy ? "Unknown operation" : "Idle")
    }

    var cloudIngestionStage: CloudIngestionStage {
        guard isCloudConfigured else { return .localOnly }
        guard isInitialized else { return .needsInitialization }
        guard requestedConsent.allowCloud else { return .needsCloudConsent }
        guard deviceAuthStatus?.isRegistered == true else { return .needsDeviceRegistration }
        guard effectiveConsent?.cloudUpload == true else { return .needsCloudAuthorization }
        guard hasBehaviorConsent else { return .needsCollectionConsent }
        if isRunning { return .collecting }
        if uploadStatus.lastFailure != nil || lastFlushResult?.failure != nil {
            return .uploadFailed
        }
        if uploadStatus.queueLength > 0 { return .readyToUpload }
        if currentCloudTestIsVerified {
            return .verified
        }
        if cloudTestHasFinalizedSession
            || (lastFlushResult?.success == true && lastFlushResult?.uploaded == 0) {
            return .noArtifacts
        }
        return .readyToCollect
    }

    private var currentCloudTestIsVerified: Bool {
        if (lastFlushResult?.uploaded ?? 0) > 0 { return true }
        guard let lastUploadAt = uploadStatus.lastUploadAt else { return false }
        guard let baseline = cloudTestBaselineUploadAt else {
            // No guided run has started in this process, so report the native
            // runtime's durable historical success honestly.
            return true
        }
        return lastUploadAt > baseline
    }

    var activatedFeatureNames: String {
        let names = Synheart.activatedFeatures().map(\.rawValue).sorted()
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    var behaviorBreakdownDescription: String {
        behaviorEventBreakdown
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
    }

    func persistIdentity() {
        let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubjectId = subjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAppId.isEmpty, !trimmedSubjectId.isEmpty else {
            report(ExampleError.operation("App ID and subject ID are required"), operation: "Save identity")
            return
        }
        appId = trimmedAppId
        subjectId = trimmedSubjectId
        defaults.set(appId, forKey: "example.appId")
        defaults.set(subjectId, forKey: "example.subjectId")
        reportSuccess("Developer identity saved")
    }

    func initializeSDK() async {
        await perform("Initialize SDK") {
            self.defaults.set(self.appId, forKey: "example.appId")
            if !CommandLine.arguments.contains("--run-parity-probe") {
                self.defaults.set(self.subjectId, forKey: "example.subjectId")
            }

            let config = SynheartConfig(
                appId: self.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                subjectId: self.subjectId.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                appName: "Synheart Core Example",
                category: "developer_tool",
                developer: "Synheart",
                deviceId: self.deviceId,
                storage: StorageConfig(enabled: true, retentionDays: 30),
                sync: SyncConfig(
                    enabled: self.isCloudConfigured,
                    baseUrl: self.environment.cloudBaseUrl ?? ApiEndpoints.defaultCloudBaseUrl
                ),
                cloudConfig: self.makeCloudConfig(),
                consentConfig: self.makeConsentConfig(),
                deviceAuthConfig: self.makeDeviceAuthConfig(),
                allowUnsignedCapabilities: self.allowUnsignedCapabilities
            )

            try await Synheart.initialize(config: config)
            self.installSubscriptions()
            self.refreshPublicState()
            self.appendEvent("SDK initialized in \(self.modeDescription.lowercased()) mode")
        }
    }

    /// Runs only when the example is launched with
    /// `--run-session-stop-probe`. It exercises the SDK lifecycle without any
    /// SwiftUI button or gesture in the path and leaves a durable timeline in
    /// the app container for device-side diagnosis.
    func runAutomatedSessionStopProbeIfRequested() async {
        let runsFullProbe = CommandLine.arguments.contains("--run-session-stop-probe")
        let runsPostHSIProbe = CommandLine.arguments.contains("--run-post-hsi-stop-probe")
        let preparesUITest = CommandLine.arguments.contains("--prepare-session-stop-ui-test")
        let probesCloudRegistration = CommandLine.arguments.contains("--probe-cloud-registration")
        guard (runsFullProbe || runsPostHSIProbe || preparesUITest || probesCloudRegistration),
              !automatedProbeHasRun else {
            return
        }
        automatedProbeHasRun = true
        recordAutomatedProbe("launch")

        await initializeSDK()
        guard isInitialized else {
            recordAutomatedProbe("failed_initialize", detail: lastError)
            return
        }
        recordAutomatedProbe("initialized")

        if probesCloudRegistration {
            guard isCloudConfigured else {
                recordAutomatedProbe("failed_cloud_configuration")
                return
            }
            recordAutomatedProbe("cloud_configuration_loaded")
            await registerDevice()
            refreshRuntimeData()
            if deviceAuthStatus?.isRegistered == true {
                recordAutomatedProbe(
                    "device_registered",
                    detail: "attestation=\(deviceAuthStatus?.attestation ?? "unknown")"
                )
            } else {
                recordAutomatedProbe(
                    "device_registration_failed",
                    detail: lastError ?? deviceAuthStatus?.status ?? "unknown"
                )
            }
            return
        }

        do {
            let repaired = try Synheart.sweepOrphanSessions(olderThan: 0)
            recordAutomatedProbe("orphans_repaired", detail: "count=\(repaired)")
        } catch {
            recordAutomatedProbe("orphan_repair_failed", detail: error.localizedDescription)
        }

        await setConsent(.behavior, enabled: true)
        guard effectiveConsent?.behavior == true else {
            recordAutomatedProbe("failed_behavior_consent", detail: lastError)
            return
        }
        recordAutomatedProbe("behavior_consent_granted")

        await startSession()
        guard isRunning, let sessionId = currentSession?.sessionId else {
            recordAutomatedProbe("failed_start", detail: lastError)
            return
        }
        recordAutomatedProbe("session_started", detail: sessionId)

        if preparesUITest {
            recordAutomatedProbe("ui_test_ready", detail: sessionId)
            return
        }

        let collectionWait: UInt64 = runsPostHSIProbe ? 70 : 2
        try? await Task.sleep(nanoseconds: collectionWait * 1_000_000_000)
        recordAutomatedProbe(
            "pre_stop_collection",
            detail: "behavior=\(behaviorEventCount), hsi=\(typedStateCount), with_data=\(dataBearingStateCount)"
        )
        recordAutomatedProbe("direct_stop_call_started", detail: sessionId)
        await stopSession()
        refreshPublicState()

        let catalogState: String
        do {
            catalogState = try Synheart.listSessions()
                .first(where: { $0.sessionId == sessionId })
                .map { $0.isActive ? "active" : "closed" }
                ?? "missing"
        } catch {
            catalogState = "query_failed: \(error.localizedDescription)"
        }
        recordAutomatedProbe(
            isRunning ? "failed_still_running" : "completed",
            detail: "session=\(sessionId), catalog=\(catalogState)"
        )
        if runsPostHSIProbe {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            refreshPublicState()
            recordAutomatedProbe(
                "post_stop_settled",
                detail: "sdk_running=\(Synheart.isRunning), sdk_session=\(Synheart.currentSession?.sessionId ?? "none"), ui_running=\(isRunning)"
            )
        }
    }

    func setConsent(_ kind: ConsentKind, enabled: Bool) async {
        guard isInitialized else { return }

        let updated = consentForm(
            requestedConsent,
            setting: kind,
            enabled: enabled
        )
        guard updated != requestedConsent else { return }

        // Update SwiftUI immediately. Native persistence is serialized below,
        // so rapid changes coalesce into the newest complete form rather than
        // being dropped by the general SDK busy guard.
        requestedConsent = updated
        appendEvent("\(kind.title) requested: \(enabled ? "on" : "off")")

        if isSavingConsent {
            await withCheckedContinuation { continuation in
                consentSaveWaiters.append(continuation)
            }
            return
        }

        await persistPendingConsent()
    }

    private func consentForm(
        _ form: ConsentForm,
        setting kind: ConsentKind,
        enabled: Bool
    ) -> ConsentForm {
        switch kind {
        case .biosignals:
            return form.copyWith(biosignals: enabled)
        case .behavior:
            return form.copyWith(behavior: enabled)
        case .phoneContext:
            return form.copyWith(phoneContext: enabled)
        case .cloudUpload:
            return form.copyWith(
                consentTier: enabled ? .cloud : .local,
                allowCloud: enabled
            )
        case .syni:
            return form.copyWith(syni: enabled)
        case .vendorSync:
            return form.copyWith(allowVendorSync: enabled)
        case .research:
            return form.copyWith(allowResearch: enabled)
        }
    }

    private func persistPendingConsent() async {
        isSavingConsent = true
        lastError = nil
        lastSuccess = nil
        defer {
            isSavingConsent = false
            consentSaveWaiters.forEach { $0.resume() }
            consentSaveWaiters.removeAll()
        }

        while requestedConsent != confirmedRequestedConsent {
            let form = requestedConsent
            do {
                _ = try await Synheart.submitConsentForm(
                    form,
                    deviceId: deviceId,
                    platform: "ios",
                    userId: subjectId
                )
                confirmedRequestedConsent = Synheart.editableConsentForm ?? form
                refreshPublicState()

                // If no newer tap arrived during native I/O, display the
                // runtime's canonical editable form. Otherwise the loop saves
                // the newer local draft next.
                if requestedConsent == form {
                    requestedConsent = confirmedRequestedConsent
                }
                appendEvent("Data permissions saved")
            } catch {
                // The UI must never claim an unsaved choice. Restore the last
                // native-confirmed form and clearly report the failure.
                requestedConsent = confirmedRequestedConsent
                report(error, operation: "Update data permissions")
                return
            }
        }
    }

    func startSession() async {
        await perform("Start session") {
            if self.isCloudConfigured, self.effectiveConsent?.cloudUpload == true {
                self.cloudTestBaselineUploadAt = self.uploadStatus.lastUploadAt
                self.cloudTestHasFinalizedSession = false
                self.lastFlushResult = nil
            }
            // Reset the previous session's presentation state before starting
            // collectors. Phone and behavior collectors can emit immediately;
            // clearing these values after startSession() returns would discard
            // legitimate callbacks from the new session.
            self.rawFrameCount = 0
            self.typedStateCount = 0
            self.dataBearingStateCount = 0
            self.behaviorEventCount = 0
            self.behaviorEventBreakdown = [:]
            self.motionSampleCount = 0
            self.wearSampleCount = 0
            self.wearDataSampleCount = 0
            self.lastWearSample = nil

            if self.effectiveConsent?.biosignals == true { Synheart.activate(.wear) }
            if self.effectiveConsent?.behavior == true { Synheart.activate(.behavior) }
            if self.effectiveConsent?.phoneContext == true { Synheart.activate(.phoneContext) }
            if self.effectiveConsent?.cloudUpload == true { Synheart.activate(.cloud) }

            try await Synheart.startSession()
            self.refreshPublicState()
            self.appendEvent("Session started: \(Synheart.currentSession?.sessionId ?? "unknown")")
        }
    }

    func requestSessionStart() {
        recordStartActionPhase("button_action_entered")
        Task {
            await startSession()
            recordStartActionPhase(
                isRunning ? "session_started" : "session_start_failed"
            )
        }
    }

    func requestSessionStop() {
        recordStopActionPhase("button_action_entered")
        Task { await stopSession() }
    }

    func stopSession() async {
        guard !isBusy else {
            recordStopActionPhase("rejected_busy_\(activeOperation ?? "unknown")")
            report(
                ExampleError.operation("Cannot stop while \(activeOperation ?? "another operation") is still running"),
                operation: "Stop session"
            )
            return
        }
        await perform("Stop session") {
            defer { self.refreshPublicState() }
            self.appendEvent("Session stop requested")
            self.recordStopActionPhase("sdk_call_started")
            do {
                try await Synheart.stopSession()
            } catch {
                self.recordStopActionPhase("sdk_error_\(Synheart.lastSessionStopPhase)")
                throw error
            }
            self.recordStopActionPhase("sdk_returned_\(Synheart.lastSessionStopPhase)")
            let stopReport = Synheart.lastSessionStopReport
            if self.isCloudConfigured,
               self.effectiveConsent?.cloudUpload == true,
               stopReport?.finalized == true {
                self.cloudTestHasFinalizedSession = true
            }
            if let stopReport {
                self.appendEvent(
                    "Session stopped: \(stopReport.status) "
                        + "(finalized=\(stopReport.finalized), catalog=\(stopReport.catalogClosed))"
                )
            } else {
                self.appendEvent("Session stopped")
            }
        }
    }

    func registerDevice() async {
        await registerDevice(force: false)
    }

    func reregisterDevice() async {
        await registerDevice(force: true)
    }

    private func registerDevice(force: Bool) async {
        await perform(force ? "Re-attest device" : "Register device") {
            let result = force
                ? await Synheart.reregisterDeviceAuth()
                : await Synheart.ensureDeviceAuthRegistered()
            self.lastRegistrationFailure = result.failure
            self.refreshRuntimeData()
            if let failure = result.failure {
                throw ExampleError.operation(
                    "\(failure.message) [\(failure.code), reason=\(failure.reason.rawValue), retryable=\(failure.retryable)]"
                )
            }
            guard result.success else {
                throw ExampleError.operation(
                    "Device registration did not complete (status=\(result.status.status))"
                )
            }
            self.lastRegistrationFailure = nil
            self.reportSuccess(
                force
                    ? "Device re-attested successfully (\(result.status.attestation))"
                    : "Device registered successfully (\(result.status.attestation))"
            )
        }
    }

    func flushUploads() async {
        await perform("Flush uploads") {
            let result = await Synheart.flushUploads()
            self.lastFlushResult = result
            self.refreshRuntimeData()
            if let failure = result.failure { throw ExampleError.operation(failure.message) }
            self.appendEvent("Upload flush: \(result.uploaded) uploaded, \(result.requeued) requeued")
        }
    }

    func advanceCloudIngestionTest() async {
        switch cloudIngestionStage {
        case .localOnly:
            return
        case .needsInitialization:
            await initializeSDK()
        case .needsCloudConsent:
            await setConsent(.cloudUpload, enabled: true)
        case .needsDeviceRegistration:
            await registerDevice()
        case .needsCloudAuthorization:
            await setConsent(.cloudUpload, enabled: true)
        case .needsCollectionConsent:
            await setConsent(.behavior, enabled: true)
        case .readyToCollect, .noArtifacts, .verified:
            await startSession()
        case .collecting:
            await stopSession()
        case .readyToUpload, .uploadFailed:
            await flushUploads()
        }
    }

    func cloudDiagnosticsText() -> String {
        let result = lastFlushResult
        let failure = cloudFailure
        return """
        Synheart Cloud Ingestion Diagnostics
        stage: \(cloudIngestionStage.title)
        configured: \(isCloudConfigured)
        platform_origin: \(environment.cloudBaseUrl ?? "missing")
        auth_origin: \(environment.authBaseUrl ?? environment.cloudBaseUrl ?? "missing")
        app_id: \(appId)
        package_name: \(configuredPackageName)
        org_id: \(environment.orgId ?? "missing")
        initialized: \(isInitialized)
        session_running: \(isRunning)
        session_id: \(currentSession?.sessionId ?? "none")
        device_auth: \(deviceAuthStatus?.status ?? "unavailable")
        attestation: \(deviceAuthStatus?.attestation ?? "unknown")
        cloud_consent: \(effectiveConsent?.cloudUpload == true)
        collection_consent: \(hasCollectionConsent)
        hsi_deliveries: \(typedStateCount)
        hsi_with_data: \(dataBearingStateCount)
        queue_state: \(uploadStatus.state.rawValue)
        queue_length: \(uploadStatus.queueLength)
        last_batch_id: \(uploadStatus.lastUploadBatchId ?? result?.batchId ?? "none")
        last_attempt: \(uploadStatus.lastUploadAttemptAt?.ISO8601Format() ?? "never")
        last_upload: \(uploadStatus.lastUploadAt?.ISO8601Format() ?? "never")
        uploaded: \(result?.uploaded ?? 0)
        failed: \(result?.failed ?? 0)
        requeued: \(result?.requeued ?? 0)
        failure_reason: \(failure?.reason.rawValue ?? "none")
        failure_code: \(failure?.code ?? "none")
        failure_retryable: \(failure?.retryable ?? false)
        failure_retry_after_ms: \(failure?.retryAfterMs.map(String.init) ?? "none")
        failure_message: \(failure?.message ?? "none")
        failure_detail: \(failure?.detail ?? "none")
        """
    }

    func repairOrphanSessions() async {
        await perform("Repair orphan sessions") {
            let count = try Synheart.sweepOrphanSessions()
            self.refreshRuntimeData()
            self.appendEvent("Closed \(count) orphan session(s)")
        }
    }

    func refreshRuntimeData() {
        guard isInitialized else { return }
        do {
            storageUsage = try Synheart.getStorageUsage()
            sessions = try Synheart.listSessions()
            uploadStatus = Synheart.uploadQueueStatus
            deviceAuthStatus = Synheart.deviceAuthStatus
        } catch {
            report(error, operation: "Refresh runtime data")
        }
    }

    func wipeLocalData() async {
        await perform("Wipe local data") {
            try await Synheart.wipeLocalData()
            self.latestState = nil
            self.rawHSI = ""
            self.rawFrameCount = 0
            self.typedStateCount = 0
            self.dataBearingStateCount = 0
            self.behaviorEventCount = 0
            self.behaviorEventBreakdown = [:]
            self.motionSampleCount = 0
            self.wearSampleCount = 0
            self.wearDataSampleCount = 0
            self.lastWearSample = nil
            self.refreshRuntimeData()
            self.reportSuccess("Local runtime data and baselines were wiped")
        }
    }

    func disposeSDK() async {
        await perform("Dispose SDK") {
            try await Synheart.dispose()
            self.subscriptions.removeAll()
            self.statusTimer?.cancel()
            self.statusTimer = nil
            self.isInitialized = false
            self.isRunning = false
            self.currentSession = nil
            self.effectiveConsent = nil
            self.deviceAuthStatus = nil
            self.storageUsage = nil
            self.sessions = []
            self.uploadStatus = UploadQueueStatus(state: .localOnly, queueLength: 0)
            self.lastFlushResult = nil
            self.lastRegistrationFailure = nil
            self.collectionStartupFailures = [:]
            self.latestState = nil
            self.rawHSI = ""
            self.rawFrameCount = 0
            self.typedStateCount = 0
            self.dataBearingStateCount = 0
            self.behaviorEventCount = 0
            self.behaviorEventBreakdown = [:]
            self.motionSampleCount = 0
            self.wearSampleCount = 0
            self.wearDataSampleCount = 0
            self.lastWearSample = nil
            self.cloudTestBaselineUploadAt = nil
            self.cloudTestHasFinalizedSession = false
            self.reportSuccess("SDK disposed. Secure device identity was preserved.")
        }
    }

    func clearError() { lastError = nil }
    func clearSuccess() { lastSuccess = nil }

    func reportInitializationRequired() {
        report(
            ExampleError.operation("Initialize the SDK from Setup first"),
            operation: "Open example section"
        )
    }

    func diagnosticsText() -> String {
        let required = symbolDiagnostics.missingRequiredSymbols.joined(separator: ", ")
        let optional = symbolDiagnostics.missingOptionalSymbols.joined(separator: ", ")
        let dependencies = dependencyDiagnostics.missingRequiredDependencies.joined(separator: ", ")
        let buildInfo = Synheart.runtimeBuildInfo
        return """
        Synheart Core Example Diagnostics
        mode: \(modeDescription)
        initialized: \(isInitialized)
        running: \(isRunning)
        runtime_version: \(Synheart.runtimeVersion ?? "unavailable")
        core_runtime_version: \(buildInfo?["core_runtime"] as? String ?? "unavailable")
        core_runtime_commit: \(buildInfo?["commit_sha"] as? String ?? "unavailable")
        core_runtime_dirty: \(buildInfo?["dirty"] as? Bool ?? false)
        runtime_entrypoint_found: \(symbolDiagnostics.runtimeEntrypointFound)
        runtime_compatible: \(symbolDiagnostics.isCompatible)
        external_onnx_required: \(dependencyDiagnostics.requiresExternalONNXRuntime)
        onnx_entrypoint_found: \(dependencyDiagnostics.onnxRuntimeEntrypointFound)
        runtime_dependencies_compatible: \(dependencyDiagnostics.isCompatible)
        missing_runtime_dependencies: \(dependencies.isEmpty ? "none" : dependencies)
        missing_required_symbols: \(required.isEmpty ? "none" : required)
        missing_optional_symbols: \(optional.isEmpty ? "none" : optional)
        subject_id: \(subjectId)
        device_id: \(deviceId)
        session_id: \(currentSession?.sessionId ?? "none")
        activated_features: \(activatedFeatureNames)
        effective_collection_consent: \(hasCollectionConsent)
        behavior_events: \(behaviorEventCount)
        motion_samples: \(motionSampleCount)
        hsi_deliveries: \(typedStateCount)
        hsi_with_data: \(dataBearingStateCount)
        upload_state: \(uploadStatus.state.rawValue)
        upload_queue: \(uploadStatus.queueLength)
        device_auth: \(deviceAuthStatus?.status ?? "unavailable")
        attestation: \(deviceAuthStatus?.attestation ?? "unknown")
        last_error: \(lastError ?? "none")
        """
    }

    func requestedConsentValue(for kind: ConsentKind) -> Bool {
        switch kind {
        case .biosignals: return requestedConsent.biosignals
        case .behavior: return requestedConsent.behavior
        case .phoneContext: return requestedConsent.phoneContext
        case .cloudUpload: return requestedConsent.allowCloud
        case .syni: return requestedConsent.syni
        case .vendorSync: return requestedConsent.allowVendorSync
        case .research: return requestedConsent.allowResearch
        }
    }

    func effectiveConsentValue(for kind: ConsentKind) -> Bool {
        guard let effectiveConsent else { return false }
        switch kind {
        case .biosignals: return effectiveConsent.biosignals
        case .behavior: return effectiveConsent.behavior
        case .phoneContext: return effectiveConsent.phoneContext
        case .cloudUpload: return effectiveConsent.cloudUpload
        case .syni: return effectiveConsent.syni
        case .vendorSync: return effectiveConsent.vendorSync
        case .research: return effectiveConsent.research
        }
    }

    private func makeCloudConfig() -> CloudConfig? {
        guard let baseUrl = environment.cloudBaseUrl,
              let orgId = environment.orgId else { return nil }
        return CloudConfig(
            subjectId: subjectId,
            instanceId: deviceId,
            orgId: orgId,
            baseUrl: baseUrl,
            uploadInterval: 30
        )
    }

    private func makeConsentConfig() -> ConsentConfig? {
        guard let serviceUrl = environment.consentBaseUrl ?? environment.cloudBaseUrl else { return nil }
        return ConsentConfig(
            consentServiceUrl: serviceUrl,
            appId: appId,
            deviceId: deviceId,
            userId: subjectId
        )
    }

    private func makeDeviceAuthConfig() -> DeviceAuthConfig? {
        guard let authBaseUrl = environment.authBaseUrl ?? environment.cloudBaseUrl else { return nil }
        return DeviceAuthConfig(
            authBaseUrl: authBaseUrl,
            packageName: environment.packageName ?? Bundle.main.bundleIdentifier ?? "",
            allowUnattestedDevRegistration: allowsUnattestedDevRegistration
        )
    }

    private func installSubscriptions() {
        subscriptions.removeAll()

        Synheart.onHSIUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] json in
                self?.rawHSI = json
                self?.rawFrameCount += 1
            }
            .store(in: &subscriptions)

        Synheart.onStateUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.latestState = state
                self?.typedStateCount += 1
                if state.hasDataBasis { self?.dataBearingStateCount += 1 }
            }
            .store(in: &subscriptions)

        Synheart.onBehaviorEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.behaviorEventCount += 1
                let type = String(describing: event.type)
                self?.behaviorEventBreakdown[type, default: 0] += 1
                self?.appendEvent("Behavior: \(type)")
            }
            .store(in: &subscriptions)

        Synheart.onWearSample
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                guard let self else { return }
                self.wearSampleCount += 1
                self.lastWearSample = sample
                if sample.hr != nil
                    || sample.hrvRmssd != nil
                    || sample.respRate != nil
                    || !(sample.rrIntervals?.isEmpty ?? true) {
                    self.wearDataSampleCount += 1
                }
            }
            .store(in: &subscriptions)

        Synheart.onPhoneMotionSample
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.motionSampleCount += 1 }
            .store(in: &subscriptions)

        statusTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshPublicState() }
    }

    private func refreshPublicState() {
        isInitialized = Synheart.isInitialized
        let sdkSession = Synheart.currentSession
        // A completed stop report is authoritative until the next start clears
        // it. This prevents stale native/SDK running state from making the UI
        // claim collection continues after Core confirmed it has stopped.
        let stopConfirmed = Synheart.lastSessionStopReport?.collectionStopped == true
        isRunning = !stopConfirmed && Synheart.isRunning && sdkSession != nil
        currentSession = isRunning ? sdkSession : nil
        collectionStartupFailures = Synheart.collectionStartupFailures
        if let editableConsent = Synheart.editableConsentForm {
            confirmedRequestedConsent = editableConsent
            if !isSavingConsent {
                requestedConsent = editableConsent
            }
        }
        effectiveConsent = Synheart.effectiveConsent
        refreshRuntimeData()
    }

    private func recordStopActionPhase(_ phase: String) {
        stopActionPhase = phase
        defaults.set(phase, forKey: "example.lastStopActionPhase")
        defaults.set(Synheart.lastSessionStopPhase, forKey: "example.lastSdkStopPhase")
        // This is diagnostic state for the integration example. Flush it so it
        // survives a debugger kill or native crash during session shutdown.
        defaults.synchronize()
    }

    private func recordStartActionPhase(_ phase: String) {
        startActionPhase = phase
        defaults.set(phase, forKey: "example.lastStartActionPhase")
        defaults.synchronize()
    }

    private func recordAutomatedProbe(_ phase: String, detail: String? = nil) {
        var entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "phase": phase,
            "initialized": isInitialized,
            "swift_running": isRunning,
            "active_operation": activeOperation ?? "none",
            "session_id": currentSession?.sessionId ?? "none",
            "stop_action_phase": stopActionPhase,
            "sdk_stop_phase": Synheart.lastSessionStopPhase
        ]
        entry["cloud_configured"] = isCloudConfigured
        entry["device_auth_status"] = deviceAuthStatus?.status ?? "unavailable"
        entry["device_attestation"] = deviceAuthStatus?.attestation ?? "unknown"
        if let failure = lastRegistrationFailure {
            entry["registration_failure_code"] = failure.code
            entry["registration_failure_reason"] = failure.reason.rawValue
            entry["registration_failure_message"] = failure.message
            entry["registration_failure_retryable"] = failure.retryable
            if let retryAfterMs = failure.retryAfterMs {
                entry["registration_failure_retry_after_ms"] = retryAfterMs
            }
            if let failureDetail = failure.detail {
                entry["registration_failure_detail"] = failureDetail
            }
        }
        if let detail { entry["detail"] = detail }
        if let lastError { entry["last_error"] = lastError }
        if let report = Synheart.lastSessionStopReport {
            entry["stop_report_status"] = report.status
            entry["stop_report_finalized"] = report.finalized
            entry["stop_report_catalog_closed"] = report.catalogClosed
        }
        automatedProbeTimeline.append(entry)

        do {
            let data = try JSONSerialization.data(
                withJSONObject: automatedProbeTimeline,
                options: [.prettyPrinted, .sortedKeys]
            )
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try data.write(to: documents.appendingPathComponent("session-stop-probe.json"), options: .atomic)
        } catch {
            print("SESSION_STOP_PROBE write_failed \(error.localizedDescription)")
        }
        print("SESSION_STOP_PROBE \(phase) \(detail ?? "")")
    }

    private func perform(_ operation: String, body: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        activeOperation = operation
        lastError = nil
        lastSuccess = nil
        // Publish the busy state before entering an SDK operation. Some native
        // actions immediately begin multi-second App Attest or network work;
        // yielding here gives SwiftUI a render turn so progress appears at once
        // and the interface remains visibly responsive.
        await Task.yield()
        defer {
            activeOperation = nil
            isBusy = false
        }
        do { try await body() } catch { report(error, operation: operation) }
    }

    private func report(_ error: Error, operation: String) {
        lastError = "\(operation): \(error.localizedDescription)"
        appendEvent(lastError ?? operation)
    }

    private func reportSuccess(_ message: String) {
        lastSuccess = message
        appendEvent(message)
    }

    private func appendEvent(_ message: String) {
        events.insert("\(Date.formattedTimestamp)  \(message)", at: 0)
        if events.count > 50 { events.removeLast(events.count - 50) }
    }
}

struct ExampleEnvironment {
    let appId: String?
    let cloudBaseUrl: String?
    let authBaseUrl: String?
    let consentBaseUrl: String?
    let orgId: String?
    let packageName: String?
    let tenantId: String?
    let projectId: String?

    static let current = ExampleEnvironment(
        appId: value("SYNHEART_APP_ID"),
        cloudBaseUrl: value("SYNHEART_BASE_URL") ?? value("SYNHEART_INGEST_BASE_URL"),
        authBaseUrl: value("SYNHEART_AUTH_URL") ?? value("SYNHEART_AUTH_BASE_URL"),
        consentBaseUrl: value("SYNHEART_CONSENT_BASE_URL"),
        orgId: value("SYNHEART_ORG_ID"),
        packageName: value("SYNHEART_PACKAGE_NAME"),
        tenantId: value("SYNHEART_TENANT_ID"),
        projectId: value("SYNHEART_PROJECT_ID")
    )

    private static func value(_ key: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[key]
            ?? Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }
}

private enum ExampleError: LocalizedError {
    case operation(String)
    var errorDescription: String? {
        switch self { case let .operation(message): return message }
    }
}

private extension HSIState {
    var hasDataBasis: Bool {
        [hsi.focus, hsi.arousal, hsi.capacity, hsi.sleep, hsi.stress,
         hsi.focusQuality, hsi.interruptionPressure, hsi.interactionMode]
            .contains { ($0?.confidence ?? 0) > 0 }
    }
}

private extension Date {
    static var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
