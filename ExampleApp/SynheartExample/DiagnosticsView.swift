import SwiftUI
import UIKit
import SynheartCore

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showRuntimeDetails = false
    @State private var showDependencies = false
    @State private var showRequiredSymbols = false
    @State private var showOptionalSymbols = false
    @State private var copiedDiagnostics = false

    private var runtimeIsHealthy: Bool {
        model.symbolDiagnostics.isCompatible
            && model.dependencyDiagnostics.isCompatible
    }

    private var hasRequiredIssues: Bool {
        !model.dependencyDiagnostics.missingRequiredDependencies.isEmpty
            || !model.symbolDiagnostics.missingRequiredSymbols.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    healthSummary
                }

                Section("Runtime build") {
                    LabeledContent("Runtime version", value: Synheart.runtimeVersion ?? "Unavailable")
                    LabeledContent(
                        "Core build",
                        value: Synheart.runtimeBuildInfo?["core_runtime"] as? String ?? "Unavailable"
                    )
                }

                Section {
                    ReliableDisclosureGroup("Runtime compatibility details", isExpanded: $showRuntimeDetails) {
                        VStack(spacing: 12) {
                            diagnosticRow(
                                "Entrypoint",
                                value: model.symbolDiagnostics.runtimeEntrypointFound ? "Found" : "Missing",
                                healthy: model.symbolDiagnostics.runtimeEntrypointFound
                            )
                            diagnosticRow(
                                "Required ABI",
                                value: model.symbolDiagnostics.isCompatible ? "Complete" : "Incomplete",
                                healthy: model.symbolDiagnostics.isCompatible
                            )
                            diagnosticRow(
                                "Host dependencies",
                                value: model.dependencyDiagnostics.isCompatible ? "Complete" : "Incomplete",
                                healthy: model.dependencyDiagnostics.isCompatible
                            )

                            if model.dependencyDiagnostics.requiresExternalONNXRuntime {
                                diagnosticRow(
                                    "ONNX Runtime",
                                    value: model.dependencyDiagnostics.onnxRuntimeEntrypointFound ? "Found" : "Missing",
                                    healthy: model.dependencyDiagnostics.onnxRuntimeEntrypointFound
                                )
                            }

                            Divider()

                            detailRow(
                                "Source commit",
                                String(
                                    (Synheart.runtimeBuildInfo?["commit_sha"] as? String ?? "Unavailable")
                                        .prefix(12)
                                ),
                                monospaced: true
                            )
                            detailRow(
                                "Dirty build",
                                (Synheart.runtimeBuildInfo?["dirty"] as? Bool) == true ? "Yes" : "No"
                            )
                        }
                        .padding(.top, 10)
                    }
                }

                if hasRequiredIssues {
                    Section("Needs attention") {
                        if !model.dependencyDiagnostics.missingRequiredDependencies.isEmpty {
                            symbolDisclosure(
                                "Missing host dependencies",
                                symbols: model.dependencyDiagnostics.missingRequiredDependencies,
                                isExpanded: $showDependencies
                            )
                        }
                        if !model.symbolDiagnostics.missingRequiredSymbols.isEmpty {
                            symbolDisclosure(
                                "Missing required symbols",
                                symbols: model.symbolDiagnostics.missingRequiredSymbols,
                                isExpanded: $showRequiredSymbols
                            )
                        }
                    }
                } else {
                    Section {
                        Label(
                            "All required runtime components are available",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }

                if !model.symbolDiagnostics.missingOptionalSymbols.isEmpty {
                    Section {
                        symbolDisclosure(
                            "Unavailable optional features",
                            symbols: model.symbolDiagnostics.missingOptionalSymbols,
                            isExpanded: $showOptionalSymbols
                        )
                    }
                }

                Section {
                    Button {
                        ExampleHaptics.selection()
                        UIPasteboard.general.string = model.diagnosticsText()
                        copiedDiagnostics = true
                    } label: {
                        Label(
                            copiedDiagnostics ? "Diagnostics Copied" : "Copy Diagnostics",
                            systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Diagnostics")
            .onChange(of: runtimeIsHealthy) { healthy in
                if healthy { ExampleHaptics.success() }
            }
        }
    }

    private var healthSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtimeIsHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(runtimeIsHealthy ? .green : .orange)
                .frame(width: 32)
                .scaleEffect(runtimeIsHealthy && !reduceMotion ? 1.04 : 1)
                .animation(reduceMotion ? nil : ExampleMotion.success, value: runtimeIsHealthy)

            VStack(alignment: .leading, spacing: 4) {
                Text(runtimeIsHealthy ? "Runtime is healthy" : "Runtime needs attention")
                    .font(.title3.bold())
                Text(runtimeIsHealthy
                    ? "The required ABI and host dependencies are available."
                    : "Expand the compatibility details to see what is missing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func diagnosticRow(
        _ title: String,
        value: String,
        healthy: Bool
    ) -> some View {
        HStack {
            Label(
                title,
                systemImage: healthy ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(healthy ? .green : .red)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detailRow(
        _ title: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func symbolDisclosure(
        _ title: String,
        symbols: [String],
        isExpanded: Binding<Bool>
    ) -> some View {
        ReliableDisclosureGroup("\(title) (\(symbols.count))", isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        }
    }
}
