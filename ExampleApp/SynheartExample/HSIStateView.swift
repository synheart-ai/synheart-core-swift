import SwiftUI
import SynheartCore

struct HSIStateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Delivery") {
                    LabeledContent("Raw frames", value: "\(model.rawFrameCount)")
                    LabeledContent("Typed states", value: "\(model.typedStateCount)")
                }

                if let state = model.latestState {
                    Section("Identity") {
                        LabeledContent("HSI ID", value: state.hsiId ?? "Unavailable")
                        LabeledContent("Version", value: state.hsiVersion ?? "Unknown")
                        LabeledContent("Subject", value: state.subjectId)
                        LabeledContent("Timestamp", value: "\(state.timestampMs)")
                    }

                    Section("Axes") {
                        AxisRow(name: "Focus", axis: state.hsi.focus)
                        AxisRow(name: "Arousal", axis: state.hsi.arousal)
                        AxisRow(name: "Capacity", axis: state.hsi.capacity)
                        AxisRow(name: "Sleep", axis: state.hsi.sleep)
                        AxisRow(name: "Stress", axis: state.hsi.stress)
                    }

                    Section("Modalities") {
                        LabeledContent("Physiological", value: state.modalities.physiological ? "Present" : "Absent")
                        LabeledContent("Kinematic", value: state.modalities.kinematic ? "Present" : "Absent")
                        LabeledContent("Digital", value: state.modalities.digital ? "Present" : "Absent")
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No HSI state")
                                .font(.headline)
                            Text("Initialize the SDK, grant collection consent, and start a native session.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                }

                if !model.rawHSI.isEmpty {
                    Section("Raw HSI 1.3 JSON") {
                        Text(model.rawHSI)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Live HSI")
        }
    }
}

private struct AxisRow: View {
    let name: String
    let axis: HSIAxisValue?

    var body: some View {
        if let axis {
            LabeledContent(
                name,
                value: String(format: "%.3f  ·  %.0f%%", axis.value, axis.confidence * 100)
            )
        } else {
            LabeledContent(name, value: "Unavailable")
                .foregroundStyle(.secondary)
        }
    }
}
