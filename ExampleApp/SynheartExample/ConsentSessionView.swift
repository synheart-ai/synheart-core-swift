import SwiftUI
import SynheartCore

struct ConsentSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSessionCode = false
    @State private var showPermissionCode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    sessionGuide
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose what this test session may collect and upload.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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
                            .padding(.vertical, 4)
                            .disabled(!model.isInitialized || model.isBusy)
                        }

                        Divider()

                        Text("Effective permissions")
                            .font(.caption.bold())
                        ForEach(AppModel.ConsentKind.allCases) { kind in
                            permissionRow(
                                kind.title,
                                allowed: model.effectiveConsentValue(for: kind)
                            )
                            .padding(.vertical, 4)
                        }

                        Text("The runtime may enforce stricter permissions than the saved choices based on app policy and verified device identity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Data permissions")
                        Spacer()
                        if model.isSavingConsent {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving data permissions")
                        }
                        CodeSnippetButton(accessibilityLabel: "View current data permission code") {
                            ExampleHaptics.selection()
                            showPermissionCode = true
                        }
                    }
                }

                if model.isRunning || hasCollectionActivity {
                    Section("Live collection") {
                        metricRow(
                            "Behavior events",
                            model.behaviorEventCount,
                            accessibilityIdentifier: "session.metric.behavior"
                        )
                        metricRow(
                            "Motion samples",
                            model.motionSampleCount,
                            accessibilityIdentifier: "session.metric.motion"
                        )
                        metricRow(
                            "HSI deliveries",
                            model.typedStateCount,
                            accessibilityIdentifier: "session.metric.hsiDeliveries"
                        )
                        metricRow(
                            "HSI with data",
                            model.dataBearingStateCount,
                            accessibilityIdentifier: "session.metric.hsiWithData"
                        )

                        LabeledContent("HSI progress") {
                            Text(hsiProgressLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(model.dataBearingStateCount > 0 ? .green : .secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        Text(model.isRunning
                            ? hsiCollectionGuidance
                            : "These counts are from the most recent session in this app process.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Technical session details") {
                    VStack(spacing: 12) {
                        detailRow("Session ID", model.currentSession?.sessionId ?? "None", monospaced: true)
                        detailRow("Activated features", model.activatedFeatureNames)
                        detailRow("Active operation", model.operationStateDescription)
                        detailRow("Start action", model.startActionPhase)
                        detailRow("Stop action", model.stopActionPhase)
                        detailRow("SDK stop phase", Synheart.lastSessionStopPhase)

                        if !model.collectionStartupFailures.isEmpty {
                            Divider()
                            ForEach(
                                model.collectionStartupFailures.sorted(by: { $0.key < $1.key }),
                                id: \.key
                            ) { name, reason in
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(
                                        "\(name) collector did not start",
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .foregroundStyle(.orange)
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Section("Lifecycle events") {
                    Group {
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
            }
            .navigationTitle("Session")
            .onChange(of: model.isRunning) { _ in
                ExampleHaptics.success()
            }
            .sheet(isPresented: $showSessionCode) {
                SwiftCodeSheet(
                    snippet: ExampleCodeSnippets.session(
                        effectiveConsent: model.effectiveConsent,
                        isRunning: model.isRunning
                    )
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPermissionCode) {
                SwiftCodeSheet(
                    snippet: ExampleCodeSnippets.permissions(model.requestedConsent)
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .safeAreaInset(edge: .bottom) {
                bottomAction
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private var sessionGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: guideIcon)
                    .font(.title2)
                    .foregroundStyle(guideColor)
                    .frame(width: 32)
                    .scaleEffect(model.isRunning && !reduceMotion ? 1.04 : 1)
                    .animation(reduceMotion ? nil : ExampleMotion.success, value: model.isRunning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(guideTitle)
                        .font(.title3.bold())
                    Text(guideMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CodeSnippetButton(accessibilityLabel: "View session lifecycle code") {
                    ExampleHaptics.selection()
                    showSessionCode = true
                }
            }

            VStack(spacing: 10) {
                guideStatusRow(
                    "SDK",
                    detail: model.isInitialized ? "Ready" : "Not initialized",
                    complete: model.isInitialized
                )
                guideStatusRow(
                    "Collection permission",
                    detail: model.hasBehaviorConsent ? "Behavior allowed" : "Behavior needed",
                    complete: model.hasBehaviorConsent
                )
                if model.isCloudConfigured {
                    guideStatusRow(
                        "Cloud upload",
                        detail: model.effectiveConsent?.cloudUpload == true ? "Allowed" : "Optional",
                        complete: model.effectiveConsent?.cloudUpload == true
                    )
                }
                guideStatusRow(
                    "Session",
                    detail: model.isStoppingSession
                        ? "Finalizing"
                        : (model.isRunning ? "Running" : "Stopped"),
                    complete: model.isRunning && !model.isStoppingSession
                )
            }

            if model.isInitialized && !model.hasBehaviorConsent {
                Button {
                    ExampleHaptics.selection()
                    Task { await model.setConsent(.behavior, enabled: true) }
                } label: {
                    Label("Enable Recommended Behavior Test", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.isRunning)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.hasBehaviorConsent)
    }

    @ViewBuilder
    private var bottomAction: some View {
        if model.isRunning {
            Button {
                ExampleHaptics.selection()
                model.requestSessionStop()
            } label: {
                Label(
                    model.isStoppingSession ? "Stopping Session…" : "Stop & Finalize Session",
                    systemImage: model.isStoppingSession ? "hourglass" : "stop.circle.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("session.stop")
        } else if model.isInitialized && !model.hasBehaviorConsent {
            Button {
                ExampleHaptics.selection()
                Task { await model.setConsent(.behavior, enabled: true) }
            } label: {
                Label("Enable Behavior Test", systemImage: "checkmark.shield.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
            .accessibilityIdentifier("session.enableBehavior")
        } else {
            Button {
                ExampleHaptics.selection()
                model.requestSessionStart()
            } label: {
                Label("Start Test Session", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("session.start")
            .disabled(!model.canStartSession || !model.hasBehaviorConsent)
        }
    }

    private var hasCollectionActivity: Bool {
        model.behaviorEventCount > 0
            || model.motionSampleCount > 0
            || model.typedStateCount > 0
            || model.dataBearingStateCount > 0
    }

    private var guideTitle: String {
        if !model.isInitialized { return "Complete Setup first" }
        if model.isStoppingSession { return "Finalizing session" }
        if model.isRunning { return "Session is running" }
        if model.isSavingConsent { return "Saving permissions" }
        if !model.hasBehaviorConsent { return "Enable behavior data" }
        return "Ready to start"
    }

    private var guideMessage: String {
        if !model.isInitialized {
            return "Return to Setup and initialize the SDK before starting a test."
        }
        if model.isStoppingSession {
            return "The runtime is closing the catalog entry and finalizing artifacts."
        }
        if model.isRunning {
            return hsiCollectionGuidance
        }
        if model.isSavingConsent {
            return "Your latest choices are visible immediately and are being saved in order."
        }
        if !model.hasBehaviorConsent {
            return "Behavior is the easiest source for testing without a wearable."
        }
        return "Your permissions are ready. Start a session and interact with the app."
    }

    private var guideIcon: String {
        if model.isStoppingSession { return "hourglass.circle.fill" }
        if model.isRunning { return "waveform.path.ecg" }
        if model.canStartSession && model.hasBehaviorConsent { return "checkmark.circle.fill" }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var guideColor: Color {
        if model.isRunning || (model.canStartSession && model.hasBehaviorConsent) { return .green }
        return .blue
    }

    private func guideStatusRow(
        _ title: String,
        detail: String,
        complete: Bool
    ) -> some View {
        HStack(spacing: 10) {
            AnimatedStatusIcon(complete: complete)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func permissionRow(_ title: String, allowed: Bool) -> some View {
        HStack {
            Label(
                title,
                systemImage: allowed ? "checkmark.circle.fill" : "minus.circle"
            )
            Spacer()
            Text(allowed ? "Allowed" : "Blocked")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(allowed ? .green : .secondary)
    }

    private var hsiProgressLabel: String {
        if model.dataBearingStateCount > 0 { return "Data received" }
        if model.typedStateCount > 0 { return "Next window pending" }
        return "First window pending"
    }

    private var hsiCollectionGuidance: String {
        if model.dataBearingStateCount > 0 {
            return "A data-bearing HSI is ready. Stop the session when you are finished testing."
        }
        if model.typedStateCount > 0 {
            return "The first window had no axis data. Keep tapping and scrolling for about another 60 seconds."
        }
        return "Keep tapping and scrolling. The first HSI arrives around 60 seconds; behavior-derived axes normally require the following window."
    }

    private func metricRow(
        _ title: String,
        _ value: Int,
        accessibilityIdentifier: String
    ) -> some View {
        LabeledContent(title) {
            // Keep a stable Text identity: replacement transitions can be
            // cached by Form rows and leave a stale visible counter.
            Text("\(value)")
                .font(.body.monospacedDigit())
                .foregroundStyle(value > 0 ? .green : .secondary)
                .accessibilityIdentifier(accessibilityIdentifier)
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
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
