import SwiftUI
import UIKit
import SynheartCore

struct HSIStateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showDeliveryDetails = false
    @State private var showTechnicalDetails = false
    @State private var showRawJSON = false
    @State private var showFormattedJSON = false
    @State private var copiedRawJSON = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hsiSummary
                }

                if let state = model.latestState {
                    Section("Live axes") {
                        AxisRow(name: "Focus", axis: state.hsi.focus)
                        AxisRow(name: "Arousal", axis: state.hsi.arousal)
                        AxisRow(name: "Capacity", axis: state.hsi.capacity)
                        AxisRow(name: "Sleep", axis: state.hsi.sleep)
                        AxisRow(name: "Stress", axis: state.hsi.stress)
                        AxisRow(name: "Focus quality", axis: state.hsi.focusQuality)
                        AxisRow(name: "Interruption pressure", axis: state.hsi.interruptionPressure)
                        AxisRow(name: "Interaction mode", axis: state.hsi.interactionMode)
                    }

                    Section {
                        ReliableDisclosureGroup("HSI technical details", isExpanded: $showTechnicalDetails) {
                            VStack(spacing: 12) {
                                detailRow("HSI ID", state.hsiId ?? "Unavailable", monospaced: true)
                                detailRow("Version", state.hsiVersion ?? "Unknown")
                                detailRow("Subject", state.subjectId, monospaced: true)
                                detailRow("Timestamp", "\(state.timestampMs)", monospaced: true)

                                Divider()

                                detailRow("Physiological modality", present(state.modalities.physiological))
                                detailRow("Kinematic modality", present(state.modalities.kinematic))
                                detailRow("Digital modality", present(state.modalities.digital))
                                detailRow("Physiological tier", state.tiers.physiological.map(String.init) ?? "None")
                                detailRow("Kinematic tier", state.tiers.kinematic.map(String.init) ?? "None")
                                detailRow("Digital tier", state.tiers.digital.map(String.init) ?? "None")
                            }
                            .padding(.top, 10)
                        }
                    }
                }

                Section {
                    ReliableDisclosureGroup("Delivery counters", isExpanded: $showDeliveryDetails) {
                        VStack(spacing: 12) {
                            detailRow("Raw frames", "\(model.rawFrameCount)")
                            detailRow("Typed states", "\(model.typedStateCount)")
                            detailRow("With data basis", "\(model.dataBearingStateCount)")
                            Text("A delivery is not the same as a measured value. An axis with zero confidence is shown as No basis.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 10)
                    }
                }

                if !model.rawHSI.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            if showRawJSON {
                                HStack(spacing: 8) {
                                    Text("Raw HSI 1.3 JSON")
                                    Spacer()

                                    Button(action: copyRawJSON) {
                                        Image(systemName: copiedRawJSON ? "checkmark" : "doc.on.doc")
                                            .font(.caption)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Copy displayed HSI JSON")

                                    Button(action: toggleJSONFormatting) {
                                        Image(systemName: "text.alignleft")
                                            .font(.caption)
                                            .foregroundStyle(showFormattedJSON ? .blue : .secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(
                                        showFormattedJSON ? "Show compact JSON" : "Show formatted JSON"
                                    )

                                    Button(action: toggleRawJSON) {
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Collapse raw HSI JSON")
                                }
                            } else {
                                Button(action: toggleRawJSON) {
                                    HStack(spacing: 8) {
                                        Text("Raw HSI 1.3 JSON")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue("Collapsed")
                            }

                            if showRawJSON {
                                Divider()
                                Group {
                                    if showFormattedJSON {
                                        Text(highlightedJSON)
                                    } else {
                                        Text(model.rawHSI)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Live HSI")
        }
    }

    private var hsiSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summaryIcon)
                    .font(.title2)
                    .foregroundStyle(summaryColor)
                    .frame(width: 32)
                    .scaleEffect(model.dataBearingStateCount > 0 && !reduceMotion ? 1.04 : 1)
                    .animation(
                        reduceMotion ? nil : ExampleMotion.success,
                        value: model.dataBearingStateCount > 0
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.title3.bold())
                    Text(summaryMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                summaryMetric("Deliveries", value: model.typedStateCount)
                Divider().frame(height: 34)
                summaryMetric("With data", value: model.dataBearingStateCount)
                Divider().frame(height: 34)
                summaryMetric("Raw frames", value: model.rawFrameCount)
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.latestState != nil)
    }

    private var summaryTitle: String {
        if model.latestState != nil && model.dataBearingStateCount > 0 { return "HSI data is live" }
        if model.latestState != nil { return "HSI delivery received" }
        if model.isRunning { return "Waiting for HSI" }
        return "No active HSI stream"
    }

    private var summaryMessage: String {
        if model.latestState != nil && model.dataBearingStateCount > 0 {
            return "At least one state contains a real data basis. Axis values update as new states arrive."
        }
        if model.latestState != nil {
            return "The runtime is delivering states, but the current axes do not yet have a measured basis."
        }
        if model.isRunning {
            return "Keep the session running and interact with the app. Behavior-only HSI can take about 60 seconds."
        }
        return "Start a session from the Session tab to begin receiving HSI updates."
    }

    private var summaryIcon: String {
        if model.latestState != nil && model.dataBearingStateCount > 0 { return "checkmark.seal.fill" }
        if model.isRunning || model.latestState != nil { return "waveform.path.ecg" }
        return "chart.xyaxis.line"
    }

    private var summaryColor: Color {
        if model.latestState != nil && model.dataBearingStateCount > 0 { return .green }
        if model.isRunning || model.latestState != nil { return .blue }
        return .secondary
    }

    private func summaryMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 3) {
            AnimatedMetricText(value: value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func present(_ value: Bool) -> String {
        value ? "Present" : "Absent"
    }

    private var formattedRawHSI: String {
        guard let data = model.rawHSI.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: formatted, encoding: .utf8) else {
            return model.rawHSI
        }
        return text
    }

    private var displayedRawHSI: String {
        showFormattedJSON ? formattedRawHSI : model.rawHSI
    }

    private var highlightedJSON: AttributedString {
        let text = displayedRawHSI
        let result = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)

        applyJSONColor(#"[{}\[\],:]"#, color: .tertiaryLabel, to: result, source: text)
        applyJSONColor(
            #"(?<![A-Za-z0-9_\"])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#,
            color: UIColor.systemPurple.withAlphaComponent(0.78),
            to: result,
            source: text
        )
        applyJSONColor(
            #"\b(?:true|false)\b"#,
            color: UIColor.systemOrange.withAlphaComponent(0.78),
            to: result,
            source: text
        )
        applyJSONColor(
            #"\bnull\b"#,
            color: UIColor.systemRed.withAlphaComponent(0.72),
            to: result,
            source: text
        )
        // Apply strings after scalar tokens so numbers or booleans inside a
        // quoted value stay one string color, then override object keys.
        applyJSONColor(
            #"\"(?:\\.|[^\"\\])*\""#,
            color: UIColor.systemTeal.withAlphaComponent(0.76),
            to: result,
            source: text
        )
        applyJSONColor(
            #"\"(?:\\.|[^\"\\])*\"(?=\s*:)"#,
            color: UIColor.systemBlue.withAlphaComponent(0.8),
            to: result,
            source: text
        )

        return AttributedString(result)
    }

    private func copyRawJSON() {
        UIPasteboard.general.string = displayedRawHSI
        copiedRawJSON = true
        ExampleHaptics.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedRawJSON = false
        }
    }

    private func toggleJSONFormatting() {
        ExampleHaptics.selection()
        showFormattedJSON.toggle()
    }

    private func toggleRawJSON() {
        ExampleHaptics.selection()
        showRawJSON.toggle()
    }

    private func applyJSONColor(
        _ pattern: String,
        color: UIColor,
        to attributed: NSMutableAttributedString,
        source: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private struct AxisRow: View {
    let name: String
    let axis: HSIAxisValue?

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if let axis, axis.confidence > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.3f", axis.value))
                        .font(.body.monospacedDigit())
                    Text("\(Int((axis.confidence * 100).rounded()))% confidence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(axis == nil ? "Unavailable" : "No basis")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
