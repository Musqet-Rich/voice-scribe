import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = "settings"

    var body: some View {
        Group {
            if case .ready = appState.modelState {
                TabView(selection: $selectedTab) {
                    SettingsWindowContent(appState: appState)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag("settings")

                    CorrectionsWindowContent(appState: appState)
                        .tabItem {
                            Label("Corrections", systemImage: "text.badge.checkmark")
                        }
                        .tag("corrections")

                    CallsView(appState: appState)
                        .tabItem {
                            Label("Calls", systemImage: "phone")
                        }
                        .tag("calls")

                    HistoryWindowContent(appState: appState)
                        .tabItem {
                            Label("History", systemImage: "clock")
                        }
                        .tag("history")
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
