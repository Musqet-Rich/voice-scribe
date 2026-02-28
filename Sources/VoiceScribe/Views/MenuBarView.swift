import SwiftUI

/// Main menubar popover content
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    var openSettingsWindow: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            // Status indicator
            statusSection

            Divider()

            // Quick actions
            actionButtons

            Divider()

            // Open settings window
            Button("Open Settings Window…") {
                openSettingsWindow?()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)

            Divider()

            // Quit
            Button("Quit Voice Scribe") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.headline)

            Spacer()
        }

        if appState.isRecording, let start = appState.recordingStartTime {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.red)
                TimelineView(.animation(minimumInterval: 0.1)) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    Text(String(format: "%.1fs", elapsed))
                        .monospacedDigit()
                }
                Spacer()
            }
            .font(.caption)
        }

        if let lastItem = appState.history.first {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last transcription:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(lastItem.correctedText)
                    .font(.caption)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .orange }
        if appState.modelState == .ready { return .green }
        return .gray
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        if appState.isTranscribing { return "Transcribing..." }
        switch appState.modelState {
        case .checking: return "Loading model..."
        case .ready: return "Ready"
        case .notDownloaded: return "Model Not Downloaded"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .error(let e): return "Error: \(e)"
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .disabled(appState.modelState != .ready || appState.isTranscribing)
            .frame(maxWidth: .infinity)
        }
    }
}
