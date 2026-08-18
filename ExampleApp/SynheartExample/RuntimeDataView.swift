import SwiftUI

struct RuntimeDataView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Sync") {
                    LabeledContent("Devices", value: "\(model.syncStatus?.deviceCount ?? 0)")
                    LabeledContent("Sync space", value: model.syncStatus?.syncSpaceId ?? "None")

                    Button("Sync Now") {
                        Task { await model.syncNow() }
                    }
                    .disabled(!model.isInitialized || model.isBusy)

                    if let result = model.lastSyncResult {
                        LabeledContent("Pushed", value: "\(result.pushed)")
                        LabeledContent("Pulled", value: "\(result.pulled)")
                        LabeledContent("Conflicts resolved", value: "\(result.conflictsResolved)")
                        if !result.errors.isEmpty {
                            Text(result.errors.joined(separator: "\n"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Storage") {
                    LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: model.storageUsage?.totalBytes ?? 0, countStyle: .file))
                    LabeledContent("Sessions", value: "\(model.storageUsage?.sessionCount ?? 0)")
                    LabeledContent("Artifacts", value: "\(model.storageUsage?.artifactCount ?? 0)")
                    LabeledContent("Pending sync", value: "\(model.storageUsage?.pendingSync ?? 0)")

                    Button("Refresh") { model.refreshData() }
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
            .onAppear { model.refreshData() }
        }
    }
}
