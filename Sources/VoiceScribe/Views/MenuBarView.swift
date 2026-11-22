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

        if appState.isCallRecording, let start = appState.callStartTime {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundColor(.red)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let s = Int(context.date.timeIntervalSince(start))
                    Text(String(format: "Call recording %02d:%02d", s / 60, s % 60))
                        .monospacedDigit()
                }
                Spacer()
            }
            .font(.caption)
        }

        ForEach(Array(appState.callStatus), id: \.key) { _, status in
            Label(status, systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let error = appState.lastError {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        if appState.isRecording || appState.isCallRecording { return .red }
        if appState.isTranscribing { return .orange }
        if appState.modelState == .ready { return .green }
        return .gray
    }

    private var statusText: String {
        if appState.isRecording { return "Listening..." }
        if appState.isCallRecording { return "Recording call" }
        if appState.isTranscribing { return "Transcribing..." }
        switch appState.modelState {
        case .checking: return "Loading model..."
        case .ready: return "Ready"
        case .notDownloaded: return "Model Not Downloaded"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .error(let e): return "Error: \(e)"
        }
    }

    private var hint: String {
        let hold = appState.shortcuts[.hold]?.map(\.displayName).joined(separator: " / ") ?? ""
        let call = appState.shortcuts[.call]?.first?.displayName
        var parts: [String] = []
        if !hold.isEmpty { parts.append("Hold \(hold) to dictate") }
        if let call { parts.append("\(call) to record a call") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .disabled(appState.modelState != .ready || appState.isTranscribing)
            .frame(maxWidth: .infinity)

            Button(appState.isCallRecording ? "Stop Call Recording" : "Record Call") {
                appState.toggleCallRecording()
            }
            .disabled(appState.modelState != .ready)
            .frame(maxWidth: .infinity)

            Label(appState.activeMicName, systemImage: "mic")
                .font(.caption2)
                .foregroundColor(.secondary)
                .onAppear { appState.refreshInputDevices() }

            Text(hint)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
