import SwiftUI
import UIKit
import SynheartCore

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime compatibility") {
                    StatusRow(
                        title: "Entrypoint",
                        value: model.symbolDiagnostics.runtimeEntrypointFound ? "Found" : "Missing",
                        isHealthy: model.symbolDiagnostics.runtimeEntrypointFound
                    )
                    StatusRow(
                        title: "Required ABI",
                        value: model.symbolDiagnostics.isCompatible ? "Complete" : "Incomplete",
                        isHealthy: model.symbolDiagnostics.isCompatible
                    )
                    LabeledContent("Runtime version", value: Synheart.runtimeVersion ?? "Unavailable")
                }

                SymbolListSection(
                    title: "Missing required symbols",
                    symbols: model.symbolDiagnostics.missingRequiredSymbols,
                    emptyMessage: "All required symbols are available"
                )

                SymbolListSection(
                    title: "Missing optional symbols",
                    symbols: model.symbolDiagnostics.missingOptionalSymbols,
                    emptyMessage: "All optional symbols are available"
                )

                Section {
                    Button("Copy Diagnostics") {
                        UIPasteboard.general.string = model.diagnosticsText()
                    }
                }
            }
            .navigationTitle("Diagnostics")
        }
    }
}

private struct SymbolListSection: View {
    let title: String
    let symbols: [String]
    let emptyMessage: String

    var body: some View {
        Section(title) {
            if symbols.isEmpty {
                Label(emptyMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}
