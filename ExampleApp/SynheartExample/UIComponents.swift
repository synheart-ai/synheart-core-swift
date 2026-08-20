import SwiftUI
import UIKit

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
