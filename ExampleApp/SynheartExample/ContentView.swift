import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: AppTab = .setup

    var body: some View {
        TabView(selection: $selectedTab) {
            SetupView {
                selectedTab = .session
            }
                .tabItem { Label("Setup", systemImage: "gearshape") }
                .tag(AppTab.setup)

            ConsentSessionView()
                .tabItem { Label("Session", systemImage: "waveform.path.ecg") }
                .tag(AppTab.session)

            HSIStateView()
                .tabItem { Label("HSI", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.hsi)

            RuntimeDataView()
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag(AppTab.data)

            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(AppTab.diagnostics)
        }
        .overlay(alignment: .top) {
            if let error = model.lastError {
                ErrorBanner(message: error, dismiss: model.clearError)
                    .padding()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            } else if let success = model.lastSuccess {
                SuccessBanner(message: success, dismiss: model.clearSuccess)
                    .padding()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.lastError)
        .animation(reduceMotion ? nil : ExampleMotion.gentle, value: model.lastSuccess)
        .onChange(of: model.lastError) { error in
            if error != nil { ExampleHaptics.warning() }
        }
        .onChange(of: model.lastSuccess) { success in
            guard let success else { return }
            ExampleHaptics.success()
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if model.lastSuccess == success {
                    model.clearSuccess()
                }
            }
        }
        .task {
            await model.runAutomatedSessionStopProbeIfRequested()
        }
    }
}

private enum AppTab: Hashable {
    case setup
    case session
    case hsi
    case data
    case diagnostics
}
