import SwiftUI
import SynheartCore

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let continueToSession: () -> Void

    @State private var showTechnicalDetails = false
    @State private var isContinuing = false

    private var deviceIsRegistered: Bool {
        model.deviceAuthStatus?.isRegistered == true
    }

    private var isReadyToTest: Bool {
        model.symbolDiagnostics.isCompatible
            && model.isInitialized
            && (!model.isDeviceAuthConfigured || deviceIsRegistered)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    readinessCard
                }

                if model.isDeviceAuthConfigured {
                    Section("Cloud identity") {
                        compactStatusRow(
                            title: "Device",
                            detail: deviceIsRegistered ? "Registered" : "Not registered",
                            complete: deviceIsRegistered
                        )
                        compactStatusRow(
                            title: "Security",
                            detail: attestationDescription,
                            complete: model.deviceAuthStatus?.attestation == "attested"
                        )

                        if !deviceIsRegistered && model.isInitialized {
                            Button {
                                Task { await model.registerDevice() }
                            } label: {
                                Label("Register Device", systemImage: "person.badge.key.fill")
                            }
                            .disabled(model.isBusy)
                        }
                    }
                }

                Section {
                    ReliableDisclosureGroup("Technical details", isExpanded: $showTechnicalDetails) {
                        technicalDetails
                    }
                }

                Section("Testing options") {
                    testingOptions
                }
            }
            .navigationTitle("Synheart Core")
            .onChange(of: isReadyToTest) { ready in
                if ready { ExampleHaptics.success() }
            }
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readinessIcon)
                    .font(.title2)
                    .foregroundStyle(readinessColor)
                    .frame(width: 32)
                    .scaleEffect(isReadyToTest && !reduceMotion ? 1.06 : 1)
                    .animation(reduceMotion ? nil : ExampleMotion.success, value: isReadyToTest)

                VStack(alignment: .leading, spacing: 4) {
                    Text(readinessTitle)
                        .font(.title3.bold())
                    Text(readinessMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                compactStatusRow(
                    title: "Runtime",
                    detail: model.symbolDiagnostics.isCompatible ? "Compatible" : "Unavailable",
                    complete: model.symbolDiagnostics.isCompatible
                )
                compactStatusRow(
                    title: "SDK",
                    detail: model.isInitialized ? "Initialized" : "Not initialized",
                    complete: model.isInitialized
                )
                compactStatusRow(
                    title: "Cloud",
                    detail: model.isCloudConfigured ? "Configured" : "Local only",
                    complete: model.isCloudConfigured
                )
                if model.isDeviceAuthConfigured {
                    compactStatusRow(
                        title: "Device",
                        detail: deviceIsRegistered
                            ? "Registered · \(attestationDescription)"
                            : "Registration needed",
                        complete: deviceIsRegistered
                    )
                }
            }

            primaryAction
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.isInitialized)
        .animation(reduceMotion ? nil : ExampleMotion.success, value: deviceIsRegistered)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if !model.symbolDiagnostics.isCompatible {
            Label(
                "Open Diagnostics to review the missing runtime components.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.red)
        } else if !model.isInitialized {
            Button {
                ExampleHaptics.selection()
                Task { await model.initializeSDK() }
            } label: {
                primaryButtonLabel(
                    model.isBusy ? "Initializing…" : "Initialize SDK",
                    systemImage: "power"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canInitialize || model.isBusy)
        } else if model.isDeviceAuthConfigured && !deviceIsRegistered {
            Button {
                ExampleHaptics.selection()
                Task { await model.registerDevice() }
            } label: {
                primaryButtonLabel(
                    model.isBusy ? "Registering…" : "Register Device",
                    systemImage: "person.badge.key.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        } else {
            Button(action: continueWithFeedback) {
                primaryButtonLabel("Continue to Session", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .scaleEffect(isContinuing && !reduceMotion ? 0.985 : 1)
            .opacity(isContinuing ? 0.92 : 1)
            .animation(reduceMotion ? nil : ExampleMotion.quick, value: isContinuing)
        }
    }

    private var technicalDetails: some View {
        VStack(spacing: 12) {
            detailRow("Mode", model.modeDescription)
            detailRow("Runtime version", Synheart.runtimeVersion ?? "Unavailable")
            detailRow(
                "Native ABI",
                model.symbolDiagnostics.isCompatible ? "Compatible" : "Incomplete"
            )
            detailRow("Platform app ID", model.appId, monospaced: true)
            detailRow("iOS bundle ID", model.configuredPackageName, monospaced: true)
            detailRow("Subject ID", model.subjectId, monospaced: true)
            detailRow("Stable device ID", model.deviceId, monospaced: true)

            if let organization = model.environment.orgId {
                detailRow("Organization", organization, monospaced: true)
            }
            if let project = model.environment.projectId {
                detailRow("Project", project, monospaced: true)
            }
            if let tenant = model.environment.tenantId {
                detailRow("Tenant", tenant, monospaced: true)
            }
            detailRow(
                "Platform origin",
                model.environment.cloudBaseUrl ?? "Not configured",
                monospaced: true
            )
            detailRow(
                "Authentication origin",
                model.environment.authBaseUrl ?? model.environment.cloudBaseUrl ?? "Not configured",
                monospaced: true
            )

            Text("Full ABI, dependency, and symbol reports are available in Diagnostics.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var testingOptions: some View {
        Toggle("Allow unsigned capabilities", isOn: $model.allowUnsignedCapabilities)

        Text("This Debug-only option supports local testing. Production cloud flows use verified device identity and consent.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if model.isInitialized && model.isDeviceAuthConfigured {
            Button {
                ExampleHaptics.selection()
                Task { await model.reregisterDevice() }
            } label: {
                operationLabel(
                    model.activeOperation == "Re-attest device"
                        ? "Re-attesting…"
                        : "Re-attest Device",
                    systemImage: "arrow.clockwise.shield",
                    isWorking: model.activeOperation == "Re-attest device"
                )
            }
            .disabled(model.isBusy)
        }

        if model.isInitialized {
            Button(role: .destructive) {
                ExampleHaptics.selection()
                Task { await model.disposeSDK() }
            } label: {
                operationLabel(
                    model.activeOperation == "Dispose SDK" ? "Disposing…" : "Dispose SDK",
                    systemImage: "power",
                    isWorking: model.activeOperation == "Dispose SDK"
                )
            }
            .disabled(model.isBusy)
        }
    }

    private func operationLabel(
        _ title: String,
        systemImage: String,
        isWorking: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var readinessTitle: String {
        if isReadyToTest { return "Ready to test" }
        if !model.symbolDiagnostics.isCompatible { return "Runtime unavailable" }
        if !model.isInitialized { return "Initialize the SDK" }
        return "Finish device setup"
    }

    private var readinessMessage: String {
        if isReadyToTest {
            return "The SDK and device identity are ready. Continue to grant consent and start a session."
        }
        if !model.symbolDiagnostics.isCompatible {
            return "The native runtime is incomplete. Diagnostics shows exactly what is missing."
        }
        if !model.isInitialized {
            return "One tap prepares the runtime and restores any saved device identity."
        }
        return "Register this iPhone before testing cloud ingestion."
    }

    private var readinessIcon: String {
        if isReadyToTest { return "checkmark.seal.fill" }
        if !model.symbolDiagnostics.isCompatible { return "xmark.octagon.fill" }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var readinessColor: Color {
        if isReadyToTest { return .green }
        if !model.symbolDiagnostics.isCompatible { return .red }
        return .blue
    }

    private var attestationDescription: String {
        switch model.deviceAuthStatus?.attestation.lowercased() {
        case "attested": return "Attested"
        case "unattested": return "Development"
        default: return "Not checked"
        }
    }

    private var canInitialize: Bool {
        !model.appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.subjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func compactStatusRow(
        title: String,
        detail: String,
        complete: Bool
    ) -> some View {
        HStack(spacing: 10) {
            AnimatedStatusIcon(complete: complete)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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

    private func primaryButtonLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            if model.isBusy {
                ProgressView()
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
            Spacer()
            if !model.isBusy {
                Image(systemName: "chevron.right")
                    .offset(x: isContinuing && !reduceMotion ? 4 : 0)
                    .animation(reduceMotion ? nil : ExampleMotion.quick, value: isContinuing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .animation(reduceMotion ? nil : ExampleMotion.quick, value: model.isBusy)
    }

    private func continueWithFeedback() {
        ExampleHaptics.selection()
        guard !reduceMotion else {
            continueToSession()
            return
        }
        withAnimation(ExampleMotion.quick) {
            isContinuing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            continueToSession()
            isContinuing = false
        }
    }
}
