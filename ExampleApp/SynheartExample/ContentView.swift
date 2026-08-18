import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gearshape") }

            ConsentSessionView()
                .tabItem { Label("Session", systemImage: "waveform.path.ecg") }

            HSIStateView()
                .tabItem { Label("HSI", systemImage: "chart.xyaxis.line") }

            RuntimeDataView()
                .tabItem { Label("Data", systemImage: "externaldrive") }

            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .overlay(alignment: .top) {
            if let error = model.lastError {
                ErrorBanner(message: error, dismiss: model.clearError)
                    .padding()
            }
        }
    }
}
