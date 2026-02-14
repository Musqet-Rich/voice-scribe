import SwiftUI

/// Displays transcription history with copy and correction actions
struct HistoryView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var correctionOriginal = ""
    @State private var correctionReplacement = ""
    @State private var showCorrectionForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcription History")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    appState.clearHistory()
                }
                .disabled(appState.history.isEmpty)
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if appState.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.history) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1fs", item.duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(item.correctedText)
                                .font(.body)
                                .textSelection(.enabled)

                            if item.text != item.correctedText {
                                Text("Original: \(item.text)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.correctedText, forType: .string)
                                }
                                .font(.caption)

                                Button("Add Correction") {
                                    correctionOriginal = item.text
                                    correctionReplacement = item.correctedText
                                    showCorrectionForm = true
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .sheet(isPresented: $showCorrectionForm) {
            CorrectionFormSheet(
                original: $correctionOriginal,
                replacement: $correctionReplacement,
                onSave: { orig, repl in
                    appState.addCorrection(original: orig, corrected: repl)
                    showCorrectionForm = false
                },
                onCancel: { showCorrectionForm = false }
            )
        }
    }
}

/// Inline correction form sheet
struct CorrectionFormSheet: View {
    @Binding var original: String
    @Binding var replacement: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Correction")
                .font(.headline)

            TextField("Original text", text: $original)
            TextField("Corrected text", text: $replacement)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    guard !original.isEmpty, !replacement.isEmpty else { return }
                    onSave(original, replacement)
                }
                .buttonStyle(.borderedProminent)
                .disabled(original.isEmpty || replacement.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
