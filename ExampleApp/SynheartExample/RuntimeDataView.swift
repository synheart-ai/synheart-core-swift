import SwiftUI

struct RuntimeDataView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Cloud ingestion") {
                    StatusRow(
                        title: "Configuration",
                        value: model.isCloudConfigured ? "Configured" : "Local only",
                        isHealthy: model.isCloudConfigured
                    )
                    StatusRow(
                        title: "Cloud consent",
                        value: model.effectiveConsent?.cloudUpload == true ? "Enforced" : "Blocked",
                        isHealthy: model.effectiveConsent?.cloudUpload == true
                    )
                    LabeledContent("Device", value: model.deviceAuthStatus?.status ?? "Unavailable")
                    LabeledContent("Attestation", value: model.deviceAuthStatus?.attestation ?? "Unknown")
                    LabeledContent("Queue", value: "\(model.uploadStatus.queueLength)")
                    LabeledContent("State", value: model.uploadStatus.state.rawValue)
                    LabeledContent("Last upload", value: model.uploadStatus.lastUploadAt?.formatted() ?? "Never")

                    if let failure = model.uploadStatus.lastFailure {
                        Text("\(failure.reason.rawValue): \(failure.message)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Flush Upload Queue") { Task { await model.flushUploads() } }
                        .disabled(!model.isInitialized || model.isBusy || !model.isCloudConfigured)

                    Text("Closed HSI windows are queued automatically by the native runtime. This app intentionally does not enqueue HSI callbacks a second time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: model.storageUsage?.totalBytes ?? 0, countStyle: .file))
                    LabeledContent("Sessions", value: "\(model.storageUsage?.sessionCount ?? 0)")
                    LabeledContent("Artifacts", value: "\(model.storageUsage?.artifactCount ?? 0)")
                    LabeledContent("Pending sync", value: "\(model.storageUsage?.pendingSync ?? 0)")

                    Button("Refresh") { model.refreshRuntimeData() }
                        .disabled(!model.isInitialized)
                    Button("Repair Orphan Sessions") {
                        Task { await model.repairOrphanSessions() }
                    }
                    .disabled(!model.isInitialized || model.isBusy)
                }

                Section("Session catalog") {
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
                        }
                    }
                }
            }
            .navigationTitle("Runtime Data")
            .onAppear { model.refreshRuntimeData() }
        }
    }
}
