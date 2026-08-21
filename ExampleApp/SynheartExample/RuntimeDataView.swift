import SwiftUI
import UIKit

struct RuntimeDataView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showStorageDetails = false
    @State private var showSessionCatalog = false

    var body: some View {
        NavigationStack {
            List {
                Section("Guided cloud ingestion test") {
                    CloudIngestionCard()
                }

                Section("On-device storage") {
                    LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: model.storageUsage?.totalBytes ?? 0, countStyle: .file))
                    LabeledContent("Pending sync", value: "\(model.storageUsage?.pendingSync ?? 0)")

                    ReliableDisclosureGroup("Storage details and tools", isExpanded: $showStorageDetails) {
                        VStack(spacing: 12) {
                            LabeledContent("Sessions", value: "\(model.storageUsage?.sessionCount ?? 0)")
                            LabeledContent("Artifacts", value: "\(model.storageUsage?.artifactCount ?? 0)")

                            Button {
                                model.refreshRuntimeData()
                            } label: {
                                Label("Refresh Storage", systemImage: "arrow.clockwise")
                            }
                            .disabled(!model.isInitialized)

                            Button {
                                Task { await model.repairOrphanSessions() }
                            } label: {
                                Label("Repair Orphan Sessions", systemImage: "wrench.and.screwdriver")
                            }
                            .disabled(!model.isInitialized || model.isBusy)
                        }
                        .padding(.top, 10)
                    }
                }

                Section {
                    ReliableDisclosureGroup(
                        "Session catalog (\(model.sessions.count))",
                        isExpanded: $showSessionCatalog
                    ) {
                        Group {
                            if model.sessions.isEmpty {
                                Text("No stored sessions")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(model.sessions, id: \.sessionId) { session in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.sessionId)
                                            .font(.caption.monospaced())
                                        Text("\(session.mode) · \(session.state)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Runtime Data")
            .onAppear { model.refreshRuntimeData() }
        }
    }
}

private struct CloudIngestionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTechnicalDetails = false
    @State private var copiedDiagnostics = false
    @State private var showCloudCode = false

    private var stage: AppModel.CloudIngestionStage { model.cloudIngestionStage }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stageIcon)
                    .font(.title2)
                    .foregroundStyle(stageColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(.headline)
                    Text(stage.guidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CodeSnippetButton(accessibilityLabel: "View cloud upload code") {
                    ExampleHaptics.selection()
                    showCloudCode = true
                }
            }

            VStack(spacing: 10) {
                checklistRow(
                    "Cloud configuration",
                    detail: model.isCloudConfigured ? "Configured" : "Local only",
                    complete: model.isCloudConfigured,
                    isCurrent: stage == .localOnly
                )
                checklistRow(
                    "SDK",
                    detail: model.isInitialized ? "Initialized" : "Not initialized",
                    complete: model.isInitialized,
                    isCurrent: stage == .needsInitialization
                )
                checklistRow(
                    "Cloud choice",
                    detail: model.requestedConsent.allowCloud ? "Requested" : "Not requested",
                    complete: model.requestedConsent.allowCloud,
                    isCurrent: stage == .needsCloudConsent
                )
                checklistRow(
                    "Device identity",
                    detail: deviceDetail,
                    complete: model.deviceAuthStatus?.isRegistered == true,
                    isCurrent: stage == .needsDeviceRegistration
                )
                checklistRow(
                    "Cloud authorization",
                    detail: model.effectiveConsent?.cloudUpload == true ? "Granted" : "Blocked",
                    complete: model.effectiveConsent?.cloudUpload == true,
                    isCurrent: stage == .needsCloudAuthorization
                )
                checklistRow(
                    "Finalized data",
                    detail: dataDetail,
                    complete: hasFinalizedData,
                    isCurrent: [.needsCollectionConsent, .readyToCollect, .collecting, .noArtifacts].contains(stage)
                )
                checklistRow(
                    "Cloud upload",
                    detail: uploadDetail,
                    complete: stage == .verified,
                    isCurrent: [.readyToUpload, .uploadFailed].contains(stage)
                )
            }

            if stage == .collecting {
                HStack {
                    LabeledContent("Behavior events") {
                        AnimatedMetricText(value: model.behaviorEventCount)
                    }
                    LabeledContent("HSI") {
                        AnimatedMetricText(value: model.typedStateCount)
                    }
                }
                .font(.caption)
            }

            if let actionTitle = stage.actionTitle {
                Button {
                    ExampleHaptics.selection()
                    Task { await model.advanceCloudIngestionTest() }
                } label: {
                    HStack {
                        if model.isBusy || model.isSavingConsent { ProgressView() }
                        Text(actionTitle)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.isSavingConsent)
            }

            if let failure = model.cloudFailure {
                VStack(alignment: .leading, spacing: 5) {
                    Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Text("\(failure.code) · \(failure.reason.rawValue)\(failure.retryable ? " · retryable" : " · permanent")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let retryAfterMs = failure.retryAfterMs {
                        Text("Suggested retry: \(retryAfterMs) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let detail = failure.detail {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            ReliableDisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Runtime state", model.uploadStatus.state.rawValue)
                    detailRow("Queue", "\(model.uploadStatus.queueLength)")
                    detailRow("Attestation", model.deviceAuthStatus?.attestation ?? "unknown")
                    detailRow("Last attempt", formatted(model.uploadStatus.lastUploadAttemptAt))
                    detailRow("Last upload", formatted(model.uploadStatus.lastUploadAt))
                    detailRow(
                        "Batch",
                        model.uploadStatus.lastUploadBatchId
                            ?? model.lastFlushResult?.batchId
                            ?? "none"
                    )
                    if let result = model.lastFlushResult {
                        detailRow(
                            "Last result",
                            "\(result.uploaded) uploaded · \(result.failed) failed · \(result.requeued) requeued"
                        )
                    }

                    Button {
                        UIPasteboard.general.string = model.cloudDiagnosticsText()
                        copiedDiagnostics = true
                    } label: {
                        Label(
                            copiedDiagnostics ? "Diagnostics Copied" : "Copy Cloud Diagnostics",
                            systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 8)
            }

            Text("The native runtime queues finalized HSI artifacts. The example does not enqueue callback deliveries a second time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: stage)
        .onChange(of: stage) { newStage in
            if newStage == .verified { ExampleHaptics.success() }
        }
        .sheet(isPresented: $showCloudCode) {
            SwiftCodeSheet(
                snippet: ExampleCodeSnippets.cloudUpload(
                    stage: model.cloudIngestionStage,
                    queueLength: model.uploadStatus.queueLength
                )
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var hasFinalizedData: Bool {
        model.uploadStatus.queueLength > 0
            || model.uploadStatus.lastUploadAt != nil
            || (model.lastFlushResult?.uploaded ?? 0) > 0
    }

    private var deviceDetail: String {
        guard let status = model.deviceAuthStatus else { return "Not checked" }
        return status.isRegistered ? "Registered · \(status.attestation)" : status.status
    }

    private var dataDetail: String {
        if model.isRunning { return "Session running · \(model.typedStateCount) HSI" }
        if model.uploadStatus.queueLength > 0 { return "\(model.uploadStatus.queueLength) queued" }
        if model.uploadStatus.lastUploadAt != nil { return "Uploaded" }
        if model.lastFlushResult?.success == true { return "No uploadable artifacts" }
        return "Not generated"
    }

    private var uploadDetail: String {
        if stage == .verified {
            let count = model.lastFlushResult?.uploaded ?? 0
            return count > 0
                ? "Ingested · \(count) artifact\(count == 1 ? "" : "s")"
                : "Ingested successfully"
        }
        if let failure = model.uploadStatus.lastFailure ?? model.lastFlushResult?.failure {
            return "Failed · \(failure.reason.rawValue)"
        }
        if model.uploadStatus.queueLength > 0 { return "Ready to flush" }
        return "Not attempted"
    }

    private var stageIcon: String {
        switch stage {
        case .localOnly: return "icloud.slash"
        case .verified: return "checkmark.seal.fill"
        case .uploadFailed, .needsCloudAuthorization: return "exclamationmark.triangle.fill"
        case .collecting: return "waveform.path.ecg"
        case .readyToUpload: return "icloud.and.arrow.up"
        default: return "arrow.triangle.2.circlepath.circle"
        }
    }

    private var stageColor: Color {
        switch stage {
        case .verified: return .green
        case .uploadFailed: return .red
        case .needsCloudAuthorization: return .orange
        case .localOnly, .noArtifacts: return .orange
        default: return .blue
        }
    }

    @ViewBuilder
    private func checklistRow(
        _ title: String,
        detail: String,
        complete: Bool,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: 10) {
            AnimatedStatusIcon(complete: complete, active: isCurrent)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.caption)
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "never"
    }
}
