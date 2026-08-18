import SwiftUI

struct ConsentSessionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Consent") {
                    ForEach(AppModel.ConsentKind.allCases) { kind in
                        Toggle(
                            kind.title,
                            isOn: Binding(
                                get: { model.consentValue(for: kind) },
                                set: { enabled in
                                    Task { await model.setConsent(kind, enabled: enabled) }
                                }
                            )
                        )
                        .disabled(!model.isInitialized || model.isBusy)
                    }

                    if !model.hasCollectionConsent {
                        Label(
                            "Grant biosignals, behavior, or phone-context consent before starting.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Native session") {
                    StatusRow(
                        title: "State",
                        value: model.isRunning ? "Running" : "Stopped",
                        isHealthy: model.isRunning
                    )
                    LabeledContent("Session ID", value: model.currentSession?.sessionId ?? "None")
                    LabeledContent("Activated features", value: model.activatedFeatureNames)

                    if model.isRunning {
                        Button("Stop Session", role: .destructive) {
                            Task { await model.stopSession() }
                        }
                        .disabled(model.isBusy)
                    } else {
                        Button("Start Session") {
                            Task { await model.startSession() }
                        }
                        .disabled(!model.canStartSession)
                    }
                }

                Section("Lifecycle events") {
                    if model.events.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.events.prefix(12).enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Consent & Session")
        }
    }
}
