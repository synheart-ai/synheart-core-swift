import SwiftUI
import UIKit
import SynheartCore

enum ExampleMotion {
    static let quick = Animation.easeOut(duration: 0.2)
    static let gentle = Animation.easeInOut(duration: 0.28)
    static let success = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

enum ExampleHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

struct SubtlePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : ExampleMotion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SubtlePressButtonStyle {
    static var subtlePress: SubtlePressButtonStyle { SubtlePressButtonStyle() }
}

struct AnimatedStatusIcon: View {
    let complete: Bool
    var active = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: complete ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle.dashed")
            .foregroundStyle(complete ? .green : active ? .blue : .secondary)
            .scaleEffect(complete && !reduceMotion ? 1.04 : 1)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : ExampleMotion.success, value: complete)
            .animation(reduceMotion ? nil : ExampleMotion.gentle, value: active)
    }
}

struct AnimatedMetricText: View {
    let value: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text("\(value)")
                .id(value)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.08)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        )
                )
        }
        .animation(reduceMotion ? nil : ExampleMotion.quick, value: value)
        .monospacedDigit()
    }
}

/// A disclosure row with an explicit full-width button target.
///
/// SwiftUI's built-in DisclosureGroup can intermittently lose parts of its
/// label hit area when it is hosted in a dynamic Form/List row. Keeping the
/// header button separate from the expanded content also prevents buttons in
/// that content from competing with the expand/collapse gesture.
struct ReliableDisclosureGroup<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    private let content: Content

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                content
            }
        }
    }

    private func toggle() {
        ExampleHaptics.selection()
        isExpanded.toggle()
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let isHealthy: Bool

    var body: some View {
        LabeledContent(title) {
            Label(value, systemImage: isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isHealthy ? .green : .red)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.footnote)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background(.red.gradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }
}

struct SuccessBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.footnote)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background(.green.gradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }
}

struct CodeSnippetButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.78))
                .frame(width: 30, height: 30)
                .background(.secondary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens a copyable Swift example")
    }
}

struct ExampleCodeSnippet {
    let title: String
    let summary: String
    let code: String
    var context: String?
}

enum ExampleCodeSnippets {
    static func initialization(
        deviceAuthConfigured: Bool,
        isInitialized: Bool
    ) -> ExampleCodeSnippet {
        if deviceAuthConfigured {
            return ExampleCodeSnippet(
                title: "Initialize the SDK",
                summary: "Minimal cloud-ready initialization using hardware-backed device identity. Replace the placeholders with values from your Synheart app configuration.",
                code: """
                import SynheartCore

                let config = SynheartConfig(
                    appId: "YOUR_PLATFORM_APP_ID",
                    subjectId: "YOUR_PSEUDONYMOUS_SUBJECT_ID",
                    storage: StorageConfig(
                        enabled: true,
                        retentionDays: 30
                    ),
                    deviceAuthConfig: DeviceAuthConfig(
                        authBaseUrl: "YOUR_AUTH_ORIGIN",
                        packageName: Bundle.main.bundleIdentifier ?? ""
                    )
                )

                try await Synheart.initialize(config: config)
                """,
                context: isInitialized ? "Cloud SDK is initialized" : "Cloud SDK is not initialized"
            )
        }

        return ExampleCodeSnippet(
            title: "Initialize the SDK",
            summary: "Minimal local initialization for Debug builds. Unsigned capabilities must never be enabled in a production app.",
            code: """
            import SynheartCore

            #if DEBUG
            let config = SynheartConfig(
                appId: "YOUR_PLATFORM_APP_ID",
                subjectId: "YOUR_PSEUDONYMOUS_SUBJECT_ID",
                allowUnsignedCapabilities: true
            )

            try await Synheart.initialize(config: config)
            #endif
            """,
            context: isInitialized ? "Local SDK is initialized" : "Local SDK is not initialized"
        )
    }

    static func permissions(_ form: ConsentForm) -> ExampleCodeSnippet {
        ExampleCodeSnippet(
            title: "Apply Data Permissions",
            summary: "This form matches the choices currently selected in the example. The runtime intersects these requests with app policy before exposing effective consent.",
            code: """
            import SynheartCore

            let form = ConsentForm(
                profileId: "YOUR_CONSENT_PROFILE_ID",
                biosignals: \(form.biosignals),
                phoneContext: \(form.phoneContext),
                behavior: \(form.behavior),
                consentTier: \(form.allowCloud ? ".cloud" : ".local"),
                allowCloud: \(form.allowCloud),
                allowResearch: \(form.allowResearch),
                allowVendorSync: \(form.allowVendorSync),
                syni: \(form.syni)
            )

            try await Synheart.submitConsentForm(
                form,
                deviceId: "YOUR_STABLE_DEVICE_ID",
                platform: "ios",
                userId: "YOUR_PSEUDONYMOUS_SUBJECT_ID"
            )
            """,
            context: "Generated from the current permission toggles"
        )
    }

    static func session(
        effectiveConsent: ConsentEffectiveState?,
        isRunning: Bool
    ) -> ExampleCodeSnippet {
        var lines = ["import SynheartCore", ""]
        var activeNames: [String] = []

        if isRunning {
            lines.append("try await Synheart.stopSession()")
            lines.append("// Finalized artifacts are now eligible for storage and upload.")
            return ExampleCodeSnippet(
                title: "Stop the Session",
                summary: "The example currently has an active session. Stopping it finalizes the session and its generated artifacts.",
                code: lines.joined(separator: "\n"),
                context: "Session running · stop is the next action"
            )
        }

        if effectiveConsent?.biosignals == true {
            lines.append("Synheart.activate(.wear)")
            activeNames.append("Biosignals")
        }
        if effectiveConsent?.behavior == true {
            lines.append("Synheart.activate(.behavior)")
            activeNames.append("Behavior")
        }
        if effectiveConsent?.phoneContext == true {
            lines.append("Synheart.activate(.phoneContext)")
            activeNames.append("Phone context")
        }
        if effectiveConsent?.cloudUpload == true {
            lines.append("Synheart.activate(.cloud)")
            activeNames.append("Cloud upload")
        }

        let hasCollectionConsent = effectiveConsent?.biosignals == true
            || effectiveConsent?.behavior == true
            || effectiveConsent?.phoneContext == true
        if hasCollectionConsent {
            lines.append("")
            lines.append("try await Synheart.startSession()")
        } else {
            lines.append("// Grant at least one collection permission before starting.")
        }

        return ExampleCodeSnippet(
            title: "Start a Session",
            summary: "Only features with effective runtime consent are activated here. App policy may make effective consent stricter than the selected permission toggles.",
            code: lines.joined(separator: "\n"),
            context: activeNames.isEmpty
                ? "No effective collection permission"
                : "Effective: " + activeNames.joined(separator: ", ")
        )
    }

    static func hsi(deliveries: Int, deliveriesWithData: Int) -> ExampleCodeSnippet {
        ExampleCodeSnippet(
            title: "Observe HSI",
            summary: "Subscribe once and retain the cancellable for as long as your UI needs typed HSI updates.",
            code: """
            import Combine
            import SynheartCore

            var cancellables = Set<AnyCancellable>()

            Synheart.onStateUpdate
                .receive(on: DispatchQueue.main)
                .sink { state in
                    print(state.hsi.focus)
                }
                .store(in: &cancellables)
            """,
            context: "This run: \(deliveries) deliveries · \(deliveriesWithData) with data"
        )
    }

    static func cloudUpload(
        stage: AppModel.CloudIngestionStage,
        queueLength: Int
    ) -> ExampleCodeSnippet {
        let title: String
        let summary: String
        let action: String

        switch stage {
        case .localOnly:
            title = "Configure Cloud Ingestion"
            summary = "Cloud ingestion is not configured in this build. Provide cloud and device-auth configuration during SDK initialization."
            action = """
            let config = SynheartConfig(
                appId: "YOUR_PLATFORM_APP_ID",
                subjectId: "YOUR_PSEUDONYMOUS_SUBJECT_ID",
                cloudConfig: YOUR_CLOUD_CONFIG,
                deviceAuthConfig: YOUR_DEVICE_AUTH_CONFIG
            )

            try await Synheart.initialize(config: config)
            """
        case .needsInitialization:
            title = "Initialize Cloud Ingestion"
            summary = "The configured SDK must be initialized before registration or upload."
            action = "try await Synheart.initialize(config: config)"
        case .needsCloudConsent, .needsCloudAuthorization:
            title = "Authorize Cloud Upload"
            summary = "Cloud upload requires an explicit user choice and an effective grant from the runtime policy."
            action = "try await Synheart.grantConsent(\"cloudUpload\")"
        case .needsDeviceRegistration:
            title = "Register Device Identity"
            summary = "Registration is idempotent. The runtime restores an existing secure identity when possible."
            action = """
            let registration = await Synheart.ensureDeviceAuthRegistered()
            print(registration.status.status)
            """
        case .needsCollectionConsent:
            title = "Enable Test Collection"
            summary = "Cloud authorization is ready, but the session still needs at least one collection permission."
            action = "try await Synheart.grantConsent(\"behavior\")"
        case .readyToCollect, .noArtifacts, .verified:
            title = "Create Uploadable Data"
            summary = "Start a consented session, interact with the app, and stop it to finalize artifacts."
            action = """
            Synheart.activate(.behavior)
            try await Synheart.startSession()
            // Interact with the app, then finalize the artifacts.
            try await Synheart.stopSession()
            """
        case .collecting:
            title = "Finalize Collection"
            summary = "A session is running. Stop it before flushing so its artifacts can enter the native queue."
            action = "try await Synheart.stopSession()"
        case .readyToUpload, .uploadFailed:
            title = stage == .uploadFailed ? "Retry Cloud Upload" : "Upload Finalized Data"
            summary = "Flush the native queue. Retryable failures remain queued for a later attempt."
            action = """
            let result = await Synheart.flushUploads()
            print("Uploaded: \\(result.uploaded)")
            """
        }

        return ExampleCodeSnippet(
            title: title,
            summary: summary,
            code: "import SynheartCore\n\n" + action,
            context: "Current stage: \(stage.title) · queue: \(queueLength)"
        )
    }

    static func testingOptions(
        isInitialized: Bool,
        deviceAuthConfigured: Bool
    ) -> ExampleCodeSnippet {
        var lines = ["import SynheartCore", ""]

        if deviceAuthConfigured {
            lines.append("// Force a fresh device registration and attestation.")
            lines.append("let registration = await Synheart.reregisterDeviceAuth()")
            lines.append("if let failure = registration.failure {")
            lines.append("    print(failure.message)")
            lines.append("}")
            lines.append("")
        } else {
            lines.append("// Re-attestation requires DeviceAuthConfig during initialization.")
            lines.append("")
        }

        lines.append("// Stop active work and release all SDK resources.")
        lines.append("try await Synheart.dispose()")

        return ExampleCodeSnippet(
            title: "Testing Utilities",
            summary: "Re-attestation repairs cloud identity without deleting local data. Disposal stops active work and releases the SDK; secure device identity remains available for the next initialization.",
            code: lines.joined(separator: "\n"),
            context: isInitialized
                ? "SDK initialized · actions available"
                : "Initialize the SDK before using these actions"
        )
    }

    static func diagnostics(
        isCompatible: Bool,
        runtimeVersion: String?
    ) -> ExampleCodeSnippet {
        ExampleCodeSnippet(
            title: "Inspect Runtime Health",
            summary: "Read build provenance and verify the native ABI and host dependencies before starting collection.",
            code: """
            import SynheartCore

            let version = Synheart.runtimeVersion
            let build = Synheart.runtimeBuildInfo
            let symbols = CoreRuntimeBridge.symbolDiagnostics
            let dependencies = CoreRuntimeBridge.dependencyDiagnostics

            print(version ?? "Runtime unavailable")
            print("ABI compatible: \\(symbols.isCompatible)")
            print("Dependencies ready: \\(dependencies.isCompatible)")
            """,
            context: "Runtime \(runtimeVersion ?? "unavailable") · ABI \(isCompatible ? "compatible" : "incomplete")"
        )
    }
}

struct SwiftCodeSheet: View {
    let snippet: ExampleCodeSnippet

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let context = snippet.context {
                        Label(context, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(snippet.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Label("Swift", systemImage: "swift")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(action: copyCode) {
                                Label(
                                    copied ? "Copied" : "Copy",
                                    systemImage: copied ? "checkmark" : "doc.on.doc"
                                )
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(copied ? "Code copied" : "Copy Swift code")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider()

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(highlightedCode)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(14)
                        }
                    }
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                    Text("The example app reads these values from local configuration rather than placing credentials in source code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(snippet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var highlightedCode: AttributedString {
        let result = NSMutableAttributedString(string: snippet.code)
        result.addAttribute(
            .foregroundColor,
            value: UIColor.label,
            range: NSRange(location: 0, length: result.length)
        )

        applySwiftColor(
            #"\b(?:import|let|try|await|true|false|nil)\b|#(?:if|endif)"#,
            color: UIColor.systemBlue.withAlphaComponent(0.82),
            to: result
        )
        applySwiftColor(
            #"\b[A-Z][A-Za-z0-9_]*\b"#,
            color: UIColor.systemPurple.withAlphaComponent(0.76),
            to: result
        )
        applySwiftColor(
            #"\"(?:\\.|[^\"\\])*\""#,
            color: UIColor.systemTeal.withAlphaComponent(0.74),
            to: result
        )
        applySwiftColor(
            #"//.*"#,
            color: UIColor.systemGreen.withAlphaComponent(0.68),
            to: result
        )

        return AttributedString(result)
    }

    private func copyCode() {
        UIPasteboard.general.string = snippet.code
        copied = true
        ExampleHaptics.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    private func applySwiftColor(
        _ pattern: String,
        color: UIColor,
        to attributed: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        regex.enumerateMatches(in: attributed.string, range: range) { match, _, _ in
            guard let match else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
