import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = "settings"

    var body: some View {
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

            HistoryWindowContent(appState: appState)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag("history")
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
