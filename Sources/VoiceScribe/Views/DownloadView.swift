import SwiftUI

/// Shows model download progress on first launch
struct DownloadView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Voice Scribe")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Download a speech recognition model to get started.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Model picker
            Picker("Model", selection: $appState.selectedModel) {
                ForEach(WhisperModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)

            switch appState.modelState {
            case .checking:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading model...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .notDownloaded:
                Button("Download Model") {
                    Task { await appState.downloadModel() }
                }
                .buttonStyle(.borderedProminent)

            case .downloading(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .error(let message):
                VStack(spacing: 8) {
                    Text("Error: \(message)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        Task { await appState.downloadModel() }
                    }
                }

            case .ready:
                Label("Model ready!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
