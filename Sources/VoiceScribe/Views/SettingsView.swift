import SwiftUI
import HotKey

/// App settings: hotkeys, model selection, about
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                // MARK: - Hotkeys Section
                Section("Hotkeys") {
                    HStack {
                        Text("Hold to talk:")
                        Spacer()
                        Text("F1")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                        Text("(change in code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Toggle recording:")
                        Spacer()
                        Text("F2")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                        Text("(change in code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Tip: Grant Accessibility permissions to VoiceScribe in System Settings → Privacy & Security → Accessibility")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Recording Section
                Section("Recording") {
                    HStack {
                        Text("Min hold duration:")
                        Slider(value: $appState.minimumHoldDuration, in: 0.1...1.0, step: 0.1)
                        Text("\(appState.minimumHoldDuration, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }

                // MARK: - Model Section
                Section("Model") {
                    Picker("Whisper model:", selection: $appState.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    switch appState.modelState {
                    case .checking:
                        Label("Loading model...", systemImage: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    case .ready:
                        Label("Model loaded", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .notDownloaded:
                        Button("Download Model") {
                            Task { await appState.downloadModel() }
                        }
                    case .downloading(let progress):
                        ProgressView(value: progress)
                    case .error(let message):
                        Text("Error: \(message)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Text("Models stored in ~/.voice-scribe/models/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - About Section
                Section("About") {
                    Text("Voice Scribe")
                        .fontWeight(.semibold)
                    Text("Local speech-to-text powered by WhisperKit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Data stored in ~/.voice-scribe/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 500)
    }
}
