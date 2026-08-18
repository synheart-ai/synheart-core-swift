import SwiftUI

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
