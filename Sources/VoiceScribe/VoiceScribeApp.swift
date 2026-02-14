import SwiftUI

/// Voice Scribe — a macOS menubar app for local speech-to-text using WhisperKit
@main
struct VoiceScribeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            switch appState.modelState {
            case .ready:
                MenuBarView(appState: appState)
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
