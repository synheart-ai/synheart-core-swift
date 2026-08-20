import SwiftUI

struct ConsentSessionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Requested choice") {
                    ForEach(AppModel.ConsentKind.allCases) { kind in
                        Toggle(
                            kind.title,
                            isOn: Binding(
                                get: { model.requestedConsentValue(for: kind) },
                                set: { enabled in
                                    Task { await model.setConsent(kind, enabled: enabled) }
                                }
                            )
                        )
                        .disabled(!model.isInitialized || model.isBusy)
                    }

                    Text("These are your saved choices. The runtime may enforce a stricter state based on app policy, device registration, or token verification.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Runtime enforced") {
                    ForEach(AppModel.ConsentKind.allCases) { kind in
                        StatusRow(
                            title: kind.title,
                            value: model.effectiveConsentValue(for: kind) ? "Allowed" : "Blocked",
                            isHealthy: model.effectiveConsentValue(for: kind)
                        )
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

                    if !model.collectionStartupFailures.isEmpty {
                        ForEach(model.collectionStartupFailures.sorted(by: { $0.key < $1.key }), id: \.key) { name, reason in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(name) collector did not start")
                                    .foregroundStyle(.orange)
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

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

                Section("Live collection proof") {
                    LabeledContent("Behavior events", value: "\(model.behaviorEventCount)")
                    LabeledContent("Motion samples", value: "\(model.motionSampleCount)")
                    LabeledContent("HSI deliveries", value: "\(model.typedStateCount)")
                    LabeledContent("HSI with data basis", value: "\(model.dataBearingStateCount)")
                    Text("For a behavior-only test, interact with the app and leave the session running for about 60 seconds. Physiological axes require a real sensor source.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
