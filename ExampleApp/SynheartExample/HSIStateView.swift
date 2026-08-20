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
                    LabeledContent("With data basis", value: "\(model.dataBearingStateCount)")
                    Text("A delivery is not the same as a measured value. An axis with zero confidence is shown as No basis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        AxisRow(name: "Focus quality", axis: state.hsi.focusQuality)
                        AxisRow(name: "Interruption pressure", axis: state.hsi.interruptionPressure)
                        AxisRow(name: "Interaction mode", axis: state.hsi.interactionMode)
                    }

                    Section("Modalities") {
                        LabeledContent("Physiological", value: state.modalities.physiological ? "Present" : "Absent")
                        LabeledContent("Kinematic", value: state.modalities.kinematic ? "Present" : "Absent")
                        LabeledContent("Digital", value: state.modalities.digital ? "Present" : "Absent")
                    }

                    Section("Source tiers") {
                        LabeledContent("Physiological", value: state.tiers.physiological.map(String.init) ?? "None")
                        LabeledContent("Kinematic", value: state.tiers.kinematic.map(String.init) ?? "None")
                        LabeledContent("Digital", value: state.tiers.digital.map(String.init) ?? "None")
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
        if let axis, axis.confidence > 0 {
            LabeledContent(
                name,
                value: String(format: "%.3f  ·  %.0f%%", axis.value, axis.confidence * 100)
            )
        } else {
            LabeledContent(name, value: axis == nil ? "Unavailable" : "No basis")
                .foregroundStyle(.secondary)
        }
    }
}
