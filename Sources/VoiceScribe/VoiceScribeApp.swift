import SwiftUI

/// Voice Scribe — a macOS menubar app for local speech-to-text using WhisperKit
@main
struct VoiceScribeApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main settings window — opens on dock icon click
        Window("Voice Scribe", id: "main") {
            MainWindowView(appState: appState)
        }
        .defaultSize(width: 550, height: 500)

        // Menubar extra — quick access
        MenuBarExtra {
            switch appState.modelState {
            case .ready:
                MenuBarView(appState: appState, openSettingsWindow: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                })
            default:
                DownloadView(appState: appState)
            }
        } label: {
            Label {
                Text("Voice Scribe")
            } icon: {
                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(appState.isRecording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
