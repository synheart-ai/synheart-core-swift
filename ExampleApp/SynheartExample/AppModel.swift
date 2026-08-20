import Combine
import Foundation
import SynheartCore

@MainActor
final class AppModel: ObservableObject {
    enum ConsentKind: String, CaseIterable, Identifiable {
        case biosignals, behavior, phoneContext, cloudUpload, syni

        var id: String { rawValue }
        var title: String {
            switch self {
            case .biosignals: return "Biosignals"
            case .behavior: return "Behavior"
            case .phoneContext: return "Phone context"
            case .cloudUpload: return "Cloud upload"
            case .syni: return "Syni personalization"
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
    @Published private(set) var requestedConsent: ConsentForm
    @Published private(set) var effectiveConsent: ConsentEffectiveState?
    @Published private(set) var currentSession: SessionHandle?
    @Published private(set) var collectionStartupFailures: [String: String] = [:]
    @Published private(set) var latestState: HSIState?
    @Published private(set) var rawHSI = ""
    @Published private(set) var rawFrameCount = 0
    @Published private(set) var typedStateCount = 0
    @Published private(set) var dataBearingStateCount = 0
    @Published private(set) var behaviorEventCount = 0
    @Published private(set) var motionSampleCount = 0
    @Published private(set) var storageUsage: StorageUsage?
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var uploadStatus = UploadQueueStatus(state: .localOnly, queueLength: 0)
    @Published private(set) var lastFlushResult: UploadFlushResult?
    @Published private(set) var deviceAuthStatus: DeviceAuthStatus?
    @Published private(set) var lastError: String?
    @Published private(set) var events: [String] = []

    let symbolDiagnostics = CoreRuntimeBridge.symbolDiagnostics
    let environment = ExampleEnvironment.current

    private var subscriptions = Set<AnyCancellable>()
    private var statusTimer: AnyCancellable?
    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        let storedSubject = defaults.string(forKey: "example.subjectId")
            ?? "example_\(UUID().uuidString.lowercased())"
        let storedDevice = defaults.string(forKey: "example.deviceId")
            ?? UUID().uuidString.lowercased()
        defaults.set(storedSubject, forKey: "example.subjectId")
        defaults.set(storedDevice, forKey: "example.deviceId")

        appId = ExampleEnvironment.current.appId
            ?? defaults.string(forKey: "example.appId")
            ?? Bundle.main.bundleIdentifier
            ?? "ai.synheart.core.example"
        subjectId = storedSubject
        deviceId = storedDevice
        requestedConsent = ConsentForm(
            profileId: "example-local",
            biosignals: false,
            phoneContext: false,
            behavior: false,
            consentTier: .local,
            allowCloud: false,
            allowResearch: false,
            allowVendorSync: false
        )
#if DEBUG
        allowUnsignedCapabilities = true
#else
        allowUnsignedCapabilities = false
#endif
    }

    var isCloudConfigured: Bool {
        environment.cloudBaseUrl != nil && environment.orgId != nil
    }

    var modeDescription: String { isCloudConfigured ? "Cloud test" : "Local only" }

    var hasCollectionConsent: Bool {
        guard let effectiveConsent else { return false }
        return effectiveConsent.biosignals || effectiveConsent.behavior || effectiveConsent.phoneContext
    }

    var canStartSession: Bool {
        isInitialized && !isRunning && hasCollectionConsent && !isBusy
    }

    var activatedFeatureNames: String {
        let names = Synheart.activatedFeatures().map(\.rawValue).sorted()
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    func initializeSDK() async {
        await perform("Initialize SDK") {
            self.defaults.set(self.appId, forKey: "example.appId")
            self.defaults.set(self.subjectId, forKey: "example.subjectId")

            let config = SynheartConfig(
                appId: self.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                subjectId: self.subjectId.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                appName: "Synheart Core Example",
                category: "developer_tool",
                developer: "Synheart",
                deviceId: self.deviceId,
                storage: StorageConfig(enabled: true, retentionDays: 30),
                sync: SyncConfig(enabled: false, baseUrl: self.environment.authBaseUrl ?? ApiEndpoints.defaultAuthBaseUrl),
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

    func setConsent(_ kind: ConsentKind, enabled: Bool) async {
        await perform("Update \(kind.title) consent") {
            let form: ConsentForm
            switch kind {
            case .biosignals:
                form = self.requestedConsent.copyWith(biosignals: enabled)
            case .behavior:
                form = self.requestedConsent.copyWith(behavior: enabled)
            case .phoneContext:
                form = self.requestedConsent.copyWith(phoneContext: enabled)
            case .cloudUpload:
                form = self.requestedConsent.copyWith(
                    consentTier: enabled ? .cloud : .local,
                    allowCloud: enabled
                )
            case .syni:
                form = self.requestedConsent.copyWith(syni: enabled)
            }

            _ = try await Synheart.submitConsentForm(
                form,
                deviceId: self.deviceId,
                platform: "ios",
                userId: self.subjectId
            )
            self.refreshPublicState()
            self.appendEvent("\(kind.title) requested: \(enabled ? "on" : "off")")
        }
    }

    func startSession() async {
        await perform("Start session") {
            if self.effectiveConsent?.biosignals == true { Synheart.activate(.wear) }
            if self.effectiveConsent?.behavior == true { Synheart.activate(.behavior) }
            if self.effectiveConsent?.phoneContext == true { Synheart.activate(.phoneContext) }
            if self.effectiveConsent?.cloudUpload == true { Synheart.activate(.cloud) }

            try await Synheart.startSession()
            self.rawFrameCount = 0
            self.typedStateCount = 0
            self.dataBearingStateCount = 0
            self.behaviorEventCount = 0
            self.motionSampleCount = 0
            self.refreshPublicState()
            self.appendEvent("Session started: \(Synheart.currentSession?.sessionId ?? "unknown")")
        }
    }

    func stopSession() async {
        await perform("Stop session") {
            try await Synheart.stopSession()
            self.refreshPublicState()
            self.appendEvent("Session stopped")
        }
    }

    func registerDevice() async {
        await perform("Register device") {
            let result = await Synheart.ensureDeviceAuthRegistered()
            self.refreshRuntimeData()
            if let failure = result.failure { throw ExampleError.operation(failure.message) }
            self.appendEvent("Device registered (\(result.status.attestation))")
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
            self.appendEvent("SDK disposed")
        }
    }

    func clearError() { lastError = nil }

    func diagnosticsText() -> String {
        let required = symbolDiagnostics.missingRequiredSymbols.joined(separator: ", ")
        let optional = symbolDiagnostics.missingOptionalSymbols.joined(separator: ", ")
        return """
        Synheart Core Example Diagnostics
        mode: \(modeDescription)
        initialized: \(isInitialized)
        running: \(isRunning)
        runtime_version: \(Synheart.runtimeVersion ?? "unavailable")
        runtime_entrypoint_found: \(symbolDiagnostics.runtimeEntrypointFound)
        runtime_compatible: \(symbolDiagnostics.isCompatible)
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
            allowUnattestedDevRegistration: true
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
                self?.appendEvent("Behavior: \(String(describing: event.type))")
            }
            .store(in: &subscriptions)

        Synheart.onPhoneMotionSample
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.motionSampleCount += 1 }
            .store(in: &subscriptions)

        statusTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshRuntimeData() }
    }

    private func refreshPublicState() {
        isInitialized = Synheart.isInitialized
        isRunning = Synheart.isRunning
        currentSession = Synheart.currentSession
        collectionStartupFailures = Synheart.collectionStartupFailures
        requestedConsent = Synheart.editableConsentForm ?? requestedConsent
        effectiveConsent = Synheart.effectiveConsent
        refreshRuntimeData()
    }

    private func perform(_ operation: String, body: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do { try await body() } catch { report(error, operation: operation) }
    }

    private func report(_ error: Error, operation: String) {
        lastError = "\(operation): \(error.localizedDescription)"
        appendEvent(lastError ?? operation)
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

    static let current = ExampleEnvironment(
        appId: value("SYNHEART_APP_ID"),
        cloudBaseUrl: value("SYNHEART_BASE_URL") ?? value("SYNHEART_INGEST_BASE_URL"),
        authBaseUrl: value("SYNHEART_AUTH_BASE_URL"),
        consentBaseUrl: value("SYNHEART_CONSENT_BASE_URL"),
        orgId: value("SYNHEART_ORG_ID"),
        packageName: value("SYNHEART_PACKAGE_NAME")
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
