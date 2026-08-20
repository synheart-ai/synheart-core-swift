import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Runtime") {
                    StatusRow(
                        title: "Native ABI",
                        value: model.symbolDiagnostics.isCompatible ? "Compatible" : "Unavailable",
                        isHealthy: model.symbolDiagnostics.isCompatible
                    )
                    StatusRow(
                        title: "SDK",
                        value: model.isInitialized ? "Initialized" : "Not initialized",
                        isHealthy: model.isInitialized
                    )

                    if !model.symbolDiagnostics.isCompatible {
                        Text("Link the Synheart native runtime to exercise sessions and sync. The app still builds and exposes the missing-symbol report under Diagnostics.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Configuration") {
                    LabeledContent("Mode", value: model.modeDescription)
                    TextField("App ID", text: $model.appId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Subject ID", text: $model.subjectId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Stable device ID", value: model.deviceId)
                    Toggle("Allow unsigned capabilities", isOn: $model.allowUnsignedCapabilities)
                    Text("Unsigned capabilities are for Debug local testing only. Production cloud flows use hardware-backed device registration and verified consent; they do not need a secret embedded in the app bundle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if model.isCloudConfigured {
                    Section("Cloud test environment") {
                        LabeledContent("Platform", value: model.environment.cloudBaseUrl ?? "Missing")
                        LabeledContent("Organization", value: model.environment.orgId ?? "Missing")
                        LabeledContent("Device status", value: model.deviceAuthStatus?.status ?? "Not checked")
                        LabeledContent("Attestation", value: model.deviceAuthStatus?.attestation ?? "Unknown")

                        Button("Register Device") {
                            Task { await model.registerDevice() }
                        }
                        .disabled(!model.isInitialized || model.isBusy)

                        Text("Real registration requires the App Attest capability and a server configured for this app and bundle identifier.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if model.isInitialized {
                        Button("Dispose SDK", role: .destructive) {
                            Task { await model.disposeSDK() }
                        }
                    } else {
                        Button("Initialize SDK") {
                            Task { await model.initializeSDK() }
                        }
                        .disabled(
                            model.isBusy
                                || model.appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.subjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
            .navigationTitle("Synheart Core")
            .overlay {
                if model.isBusy { ProgressView() }
            }
        }
    }
}
