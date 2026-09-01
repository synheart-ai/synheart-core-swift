import Foundation
import SwiftUI
import SynheartCore

enum ParityCheckStatus: String, Codable {
    case passed
    case failed
    case unavailable

    var color: Color {
        switch self {
        case .passed: return .green
        case .failed: return .red
        case .unavailable: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .unavailable: return "minus.circle.fill"
        }
    }
}

struct ParityCheckResult: Identifiable, Codable {
    let id: String
    let priority: String
    let title: String
    let status: ParityCheckStatus
    let detail: String
    let timestamp: Date
}

@MainActor
final class ParityTestRunner: ObservableObject {
    @Published private(set) var results: [ParityCheckResult] = []
    @Published private(set) var isRunning = false
    @Published private(set) var completedAt: Date?

    var summary: String {
        let passed = results.filter { $0.status == .passed }.count
        let failed = results.filter { $0.status == .failed }.count
        let unavailable = results.filter { $0.status == .unavailable }.count
        return "\(passed) passed · \(failed) failed · \(unavailable) unavailable"
    }

    func run(model: AppModel) async {
        guard !isRunning else { return }
        isRunning = true
        completedAt = nil
        results = []
        defer {
            isRunning = false
            completedAt = Date()
            writeReport(model: model)
        }

        if !model.isInitialized { await model.initializeSDK() }
        guard model.isInitialized else {
            record("P0", "SDK initialization", .failed, model.lastError ?? "Initialization did not complete")
            return
        }

        await runP0(model: model)
        await runP1(model: model)
        await runP2(model: model)
        await runP3(model: model)
        model.refreshRuntimeData()
    }

    private func runP0(model: AppModel) async {
        record(
            "P0",
            "Package version",
            SynheartCoreVersion.current.isEmpty ? .failed : .passed,
            SynheartCoreVersion.current
        )

        let diagnostics = model.symbolDiagnostics
        record(
            "P0",
            "Required runtime ABI",
            diagnostics.isCompatible ? .passed : .failed,
            diagnostics.missingRequiredSymbols.isEmpty
                ? "All required symbols resolved"
                : diagnostics.missingRequiredSymbols.joined(separator: ", ")
        )

        let hasPlatform = model.environment.cloudBaseUrl != nil
        let hasAuth = model.environment.authBaseUrl != nil || model.environment.cloudBaseUrl != nil
        record(
            "P0",
            "Explicit service origins",
            hasPlatform && hasAuth ? .passed : .unavailable,
            "platform=\(model.environment.cloudBaseUrl ?? "missing"), auth=\(model.environment.authBaseUrl ?? "missing")"
        )

        guard model.isCloudConfigured else {
            record("P0", "Device registration", .unavailable, "Cloud test configuration is absent")
            return
        }
        let registration = await Synheart.ensureDeviceAuthRegistered()
        model.refreshRuntimeData()
        record(
            "P0",
            "Device registration",
            registration.success ? .passed : .failed,
            registration.failure?.message ?? "status=\(registration.status.status), attestation=\(registration.status.attestation)"
        )
    }

    private func runP1(model: AppModel) async {
        let sleepInput = SleepScoreInput(
            tonight: NightRaw(
                wakeCalendarDate: 20260901,
                detail: .vendorScore(score: 82),
                avgHrBpm: 58
            )
        )
        if missing("synheart_core_sleep_score_compute_json", model: model) {
            record("P1", "Sleep score", .unavailable, "Optional runtime symbol is absent")
        } else if let score = Synheart.computeSleepScore(sleepInput) {
            record("P1", "Sleep score", .passed, "score=\(score.score.map(String.init) ?? "not emitted"), confidence=\(score.confidence)")
        } else {
            record("P1", "Sleep score", .failed, "Runtime returned no result")
        }

        if missing("synheart_core_baseline_hydrate_local", model: model) {
            record("P1", "Typed baseline hydration", .unavailable, "Optional runtime symbol is absent")
        } else {
            let response = await Synheart.baselineHydrateLocal()
            record(
                "P1",
                "Typed baseline hydration",
                response == nil ? .unavailable : .passed,
                response == nil ? "No baseline payload is available yet" : "\(Synheart.baselineSnapshots.all.count) typed snapshot(s) cached"
            )
        }

        guard model.isCloudConfigured else {
            record("P1", "Sync-space lifecycle", .unavailable, "Cloud test configuration is absent")
            record("P1", "Deletion dry run", .unavailable, "Cloud test configuration is absent")
            return
        }

        await model.setConsent(.cloudUpload, enabled: true)
        Synheart.activate(.synsync)
        let readiness = await Synheart.checkSyncReadiness(operation: .createSpace)
        guard readiness.isReady else {
            let snapshot = readiness.nativeSnapshot.map(jsonDescription) ?? "no native snapshot"
            record(
                "P1",
                "Sync-space lifecycle",
                .unavailable,
                "Readiness: \(readiness.code.rawValue); \(snapshot)"
            )
            await runDeletionDryRun(model: model)
            return
        }

        var createdSpace = false
        if let created = await Synheart.syncCreateSpace(deviceName: "Parity iPhone"), runtimeMapSucceeded(created) {
            createdSpace = true
            record("P1", "Create sync space", .passed, compact(created))

            let pairing = await Synheart.syncGeneratePairing()
            record(
                "P1",
                "Generate pairing",
                pairing.map(runtimeMapSucceeded) == true ? .passed : .failed,
                pairing.map(compact) ?? "Runtime returned no pairing payload"
            )

            let devices = await Synheart.syncListDevices()
            record(
                "P1",
                "List sync devices",
                devices.map(runtimeMapSucceeded) == true ? .passed : .failed,
                devices.map(compact) ?? "Runtime returned no device payload"
            )
        } else {
            record("P1", "Create sync space", .failed, "Runtime returned no successful payload")
        }

        if createdSpace {
            let deleted = await Synheart.syncDeleteSpace()
            record(
                "P1",
                "Clean up sync space",
                deleted.map(runtimeMapSucceeded) == true ? .passed : .failed,
                deleted.map(compact) ?? "Runtime returned no cleanup payload"
            )
        }
        await runDeletionDryRun(model: model)
    }

    private func runDeletionDryRun(model: AppModel) async {
        guard !missing("synheart_core_request_data_deletion", model: model) else {
            record("P1", "Deletion dry run", .unavailable, "Optional runtime symbol is absent")
            return
        }
        do {
            let request = try await Synheart.requestDataDeletion(
                reason: "Swift parity validation",
                dryRun: true
            )
            record("P1", "Deletion dry run", .passed, "request=\(request.requestId), status=\(request.statusRaw)")
        } catch {
            record("P1", "Deletion dry run", .failed, String(describing: error))
        }
    }

    private func runP2(model: AppModel) async {
        let inputSymbols = [
            "synheart_core_push_rr_batch",
            "synheart_core_push_vendor_hrv",
            "synheart_core_push_vendor_vitals",
        ]
        guard inputSymbols.allSatisfy({ !missing($0, model: model) }) else {
            record("P2", "Runtime input pipeline", .unavailable, "One or more optional input symbols are absent")
            return
        }

        await model.setConsent(.behavior, enabled: true)
        if !model.isRunning { await model.startSession() }
        let sessionStarted = model.isRunning
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        Synheart.ensurePipeline()
        Synheart.pushRrBatch(
            anchorTimestampMs: now,
            intervalsMs: (0..<90).map { 820 + Double($0 % 7) * 3 },
            provider: "swift_parity_lab"
        )
        Synheart.pushVendorHrv(timestampMs: now, rmssd: 44, sdnn: 61, stress: 0.35, recovery: 0.72)
        Synheart.pushVendorVitals(timestampMs: now, spo2: 98, respiration: 14)
        let tick = Synheart.tick(at: Date(timeIntervalSince1970: Double(now + 120_000) / 1_000))
        let features = Synheart.lastRuntimeFeatures
        record(
            "P2",
            "Runtime input pipeline",
            tick == nil && features == nil ? .unavailable : .passed,
            tick == nil && features == nil
                ? "Inputs were submitted, but this window emitted no runtime payload; session_started=\(sessionStarted)"
                : "RR, HRV and vitals accepted; session_started=\(sessionStarted)"
        )
        if missing("synheart_core_set_task_type", model: model)
            || missing("synheart_core_current_task_type", model: model) {
            record("P2", "Personalization context", .unavailable, "Optional runtime symbols are absent")
        } else {
            Synheart.setTaskType(.focus)
            Synheart.setFocusKind(.hard)
            let passed = Synheart.currentTaskType == .focus && Synheart.currentFocusKind == .hard
            record(
                "P2",
                "Personalization context",
                passed ? .passed : .failed,
                "task=\(Synheart.currentTaskType), focus=\(Synheart.currentFocusKind)"
            )
        }

        if model.isRunning { await model.stopSession() }

        if missing("synheart_core_hsi_history_count", model: model) {
            record("P2", "HSI history", .unavailable, "Optional runtime symbol is absent")
        } else {
            let count = Synheart.hsiHistoryCount
            record(
                "P2",
                "HSI history",
                count > 0 ? .passed : .unavailable,
                count > 0 ? "\(count) local window(s)" : "History API responded, but no HSI window was emitted"
            )
        }

        if let syni = Synheart.syniService {
            do {
                let sessions = try await syni.listSessions(limit: 1)
                record("P2", "Syni service", .passed, "Authenticated; \(sessions.count) session(s) returned")
            } catch let error as SyniServiceError {
                let externallyBlocked = error.code == .authentication
                    || error.code == .unsupported
                    || error.code == .unavailable
                record(
                    "P2",
                    "Syni service",
                    externallyBlocked ? .unavailable : .failed,
                    error.description
                )
            } catch {
                record("P2", "Syni service", .failed, String(describing: error))
            }
        } else {
            record("P2", "Syni service", .unavailable, "Runtime service symbols are absent")
        }

        if missing("synheart_core_init_logging_buffered", model: model) {
            record("P2", "Buffered runtime logging", .unavailable, "Optional runtime symbol is absent")
        } else {
            let initialized = RuntimeLogging.initialize(environmentFilter: "info")
            _ = RuntimeLogging.drain()
            let shutdown = RuntimeLogging.shutdown()
            record(
                "P2",
                "Buffered runtime logging",
                initialized >= 0 && shutdown >= 0 ? .passed : .failed,
                "initialize=\(initialized), shutdown=\(shutdown)"
            )
        }
    }

    private func runP3(model: AppModel) async {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("synheart-parity-\(UUID().uuidString)", isDirectory: true)
        let directoryA = base.appendingPathComponent("a", isDirectory: true)
        let directoryB = base.appendingPathComponent("b", isDirectory: true)
        var instanceA: SynheartInstance?
        var instanceB: SynheartInstance?
        defer {
            instanceA?.dispose()
            instanceB?.dispose()
            try? FileManager.default.removeItem(at: base)
        }

        do {
            let configA = localInstanceConfig(model: model, suffix: "a")
            let configB = localInstanceConfig(model: model, suffix: "b")
            instanceA = try SynheartInstance(config: configA, dataDirectory: directoryA)
            instanceB = try SynheartInstance(config: configB, dataDirectory: directoryB)
            record("P3", "Independent runtime handles", .passed, "Two unique local directories opened")

            do {
                _ = try SynheartInstance(config: configA, dataDirectory: directoryA)
                record("P3", "Duplicate-directory guard", .failed, "A duplicate directory was accepted")
            } catch {
                record("P3", "Duplicate-directory guard", .passed, "Duplicate directory rejected")
            }

            let handleA = instanceA?.startSession()
            let handleB = instanceB?.startSession()
            let unique = handleA != nil && handleB != nil && handleA?.sessionId != handleB?.sessionId
            if let instanceA, let instanceB {
                let now = Int64(Date().timeIntervalSince1970 * 1_000)
                instanceA.pushRr(timestampMs: now, intervalMs: 800, provider: "parity_a")
                instanceB.pushRr(timestampMs: now, intervalMs: 900, provider: "parity_b")
                _ = instanceA.tick()
                _ = instanceB.tick()
                _ = instanceA.stopSession()
                _ = instanceB.stopSession()
            }
            record(
                "P3",
                "Independent sessions",
                unique ? .passed : .failed,
                unique ? "Distinct session IDs and inputs" : "One or both sessions failed to start independently"
            )
        } catch {
            record("P3", "Independent runtime handles", .failed, String(describing: error))
        }
    }

    private func localInstanceConfig(model: AppModel, suffix: String) -> SynheartConfig {
        SynheartConfig(
            appId: model.appId,
            subjectId: "parity_instance_\(suffix)_\(UUID().uuidString.lowercased())",
            appVersion: "parity",
            appName: "Swift Parity Lab",
            category: "developer_tool",
            developer: "Synheart",
            deviceId: "parity_\(suffix)_\(UUID().uuidString.lowercased())",
            storage: StorageConfig(enabled: true, retentionDays: 1),
            sync: SyncConfig(enabled: false),
            allowUnsignedCapabilities: true
        )
    }

    private func missing(_ symbol: String, model: AppModel) -> Bool {
        model.symbolDiagnostics.missingOptionalSymbols.contains(symbol)
    }

    private func runtimeMapSucceeded(_ map: [String: Any]) -> Bool {
        guard map["error"] == nil else { return false }
        return map["success"] as? Bool != false
    }

    private func compact(_ map: [String: Any]) -> String {
        if let error = map["error"] as? String { return error }
        let keys = map.keys.sorted().prefix(5).joined(separator: ", ")
        return keys.isEmpty ? "Successful response" : "response keys: \(keys)"
    }

    private func jsonDescription(_ map: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(map),
              let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return compact(map)
        }
        return value
    }

    private func record(
        _ priority: String,
        _ title: String,
        _ status: ParityCheckStatus,
        _ detail: String
    ) {
        results.append(
            ParityCheckResult(
                id: "\(priority)-\(results.count)-\(title)",
                priority: priority,
                title: title,
                status: status,
                detail: detail,
                timestamp: Date()
            )
        )
    }

    private func writeReport(model: AppModel) {
        let report: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "subject_id": model.subjectId,
            "runtime_version": Synheart.runtimeVersion ?? "unavailable",
            "summary": summary,
            "results": results.map {
                [
                    "priority": $0.priority,
                    "title": $0.title,
                    "status": $0.status.rawValue,
                    "detail": $0.detail,
                    "timestamp": ISO8601DateFormatter().string(from: $0.timestamp),
                ]
            },
        ]
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let documents = try? FileManager.default.url(
                  for: .documentDirectory,
                  in: .userDomainMask,
                  appropriateFor: nil,
                  create: true
              ) else { return }
        try? data.write(to: documents.appendingPathComponent("parity-report.json"), options: .atomic)
    }
}

struct ParityLabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ParityTestRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if runner.results.isEmpty {
                Text("Runs isolated, non-destructive P0–P3 checks and saves parity-report.json.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(runner.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(runner.results) { result in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: result.status.symbol)
                            .foregroundStyle(result.status.color.opacity(0.85))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(result.priority) · \(result.title)")
                                .font(.caption.weight(.medium))
                            Text(result.detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Button {
                Task { await runner.run(model: model) }
            } label: {
                Label(runner.isRunning ? "Running parity checks…" : "Run P0–P3 checks", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(runner.isRunning || model.isBusy || model.isRunning)
        }
        .padding(.top, 8)
    }
}
