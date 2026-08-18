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
                    TextField("App ID", text: $model.appId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Subject ID", text: $model.subjectId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Allow unsigned capabilities", isOn: $model.allowUnsignedCapabilities)
                    Text("Unsigned capabilities are for local development only. Production apps should obtain a signed capability token from their backend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
