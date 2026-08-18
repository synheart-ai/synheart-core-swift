import Combine
import Foundation
import SynheartCore

@MainActor
final class AppModel: ObservableObject {
    enum ConsentKind: String, CaseIterable, Identifiable {
        case biosignals
        case behavior
        case phoneContext
        case cloudUpload
        case syni

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
    @Published var allowUnsignedCapabilities = true
    @Published private(set) var isInitialized = false
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var consent = ConsentSnapshot.none()
    @Published private(set) var currentSession: SessionHandle?
    @Published private(set) var latestState: HSIState?
    @Published private(set) var rawHSI = ""
    @Published private(set) var rawFrameCount = 0
    @Published private(set) var typedStateCount = 0
    @Published private(set) var storageUsage: StorageUsage?
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var syncStatus: SyncStatus?
    @Published private(set) var lastSyncResult: SyncResult?
    @Published private(set) var lastError: String?
    @Published private(set) var events: [String] = []

    let symbolDiagnostics = CoreRuntimeBridge.symbolDiagnostics

    private var subscriptions = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        appId = UserDefaults.standard.string(forKey: "example.appId")
            ?? Bundle.main.bundleIdentifier
            ?? "ai.synheart.core.example"
        subjectId = UserDefaults.standard.string(forKey: "example.subjectId")
            ?? "example_\(UUID().uuidString.lowercased())"
    }

    var hasCollectionConsent: Bool {
        consent.biosignals || consent.behavior || consent.phoneContext
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
                storage: StorageConfig(enabled: true, retentionDays: 30),
                sync: SyncConfig(enabled: false),
                allowUnsignedCapabilities: self.allowUnsignedCapabilities
            )

            try await Synheart.initialize(config: config)
            self.installSubscriptions()
            self.refreshPublicState()
            self.appendEvent("SDK initialized")
        }
    }

    func setConsent(_ kind: ConsentKind, enabled: Bool) async {
        await perform("Update \(kind.title) consent") {
            if enabled {
                try await Synheart.grantConsent(kind.rawValue)
            } else {
                try await Synheart.revokeConsent(kind.rawValue)
            }
            self.refreshPublicState()
            self.appendEvent("\(kind.title) consent \(enabled ? "granted" : "revoked")")
        }
    }

    func startSession() async {
        await perform("Start session") {
            if self.consent.biosignals { Synheart.activate(.wear) }
            if self.consent.behavior { Synheart.activate(.behavior) }
            if self.consent.phoneContext { Synheart.activate(.phoneContext) }
            if self.consent.cloudUpload { Synheart.activate(.cloud) }

            try await Synheart.startSession()
            self.refreshPublicState()
            self.appendEvent("Session started: \(Synheart.currentSession?.sessionId ?? "unknown")")
        }
    }

    func stopSession() async {
        await perform("Stop session") {
            try await Synheart.stopSession()
            self.refreshPublicState()
            self.appendEvent("Session stopped")
            self.refreshData()
        }
    }

    func syncNow() async {
        await perform("Sync now") {
            self.lastSyncResult = try await Synheart.syncNow()
            self.refreshData()
            self.appendEvent("Sync completed")
        }
    }

    func repairOrphanSessions() async {
        await perform("Repair orphan sessions") {
            let count = try Synheart.sweepOrphanSessions()
            self.refreshData()
            self.appendEvent("Closed \(count) orphan session(s)")
        }
    }

    func refreshData() {
        guard isInitialized else { return }
        do {
            storageUsage = try Synheart.getStorageUsage()
            sessions = try Synheart.listSessions()
            syncStatus = try Synheart.getSyncStatus()
        } catch {
            report(error, operation: "Refresh runtime data")
        }
    }

    func disposeSDK() async {
        await perform("Dispose SDK") {
            try await Synheart.dispose()
            self.subscriptions.removeAll()
            self.isInitialized = false
            self.isRunning = false
            self.currentSession = nil
            self.appendEvent("SDK disposed")
        }
    }

    func clearError() {
        lastError = nil
    }

    func diagnosticsText() -> String {
        let required = symbolDiagnostics.missingRequiredSymbols.joined(separator: ", ")
        let optional = symbolDiagnostics.missingOptionalSymbols.joined(separator: ", ")
        return """
        Synheart Core Example Diagnostics
        initialized: \(isInitialized)
        running: \(isRunning)
        runtime_version: \(Synheart.runtimeVersion ?? "unavailable")
        runtime_entrypoint_found: \(symbolDiagnostics.runtimeEntrypointFound)
        runtime_compatible: \(symbolDiagnostics.isCompatible)
        missing_required_symbols: \(required.isEmpty ? "none" : required)
        missing_optional_symbols: \(optional.isEmpty ? "none" : optional)
        subject_id: \(subjectId)
        session_id: \(currentSession?.sessionId ?? "none")
        activated_features: \(activatedFeatureNames)
        last_error: \(lastError ?? "none")
        """
    }

    func consentValue(for kind: ConsentKind) -> Bool {
        switch kind {
        case .biosignals: return consent.biosignals
        case .behavior: return consent.behavior
        case .phoneContext: return consent.phoneContext
        case .cloudUpload: return consent.cloudUpload
        case .syni: return consent.syni
        }
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
            }
            .store(in: &subscriptions)
    }

    private func refreshPublicState() {
        isInitialized = Synheart.isInitialized
        isRunning = Synheart.isRunning
        currentSession = Synheart.currentSession
        consent = Synheart.currentConsent ?? .none()
        refreshData()
    }

    private func perform(_ operation: String, body: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try await body()
        } catch {
            report(error, operation: operation)
        }
    }

    private func report(_ error: Error, operation: String) {
        lastError = "\(operation): \(error.localizedDescription)"
        appendEvent(lastError ?? operation)
    }

    private func appendEvent(_ message: String) {
        let timestamp = Date.formattedTimestamp
        events.insert("\(timestamp)  \(message)", at: 0)
        if events.count > 50 {
            events.removeLast(events.count - 50)
        }
    }
}

private extension Date {
    static var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
