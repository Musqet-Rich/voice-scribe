import SwiftUI

/// Reusable history content — used in both sheet and window tab
struct HistoryContent: View {
    @ObservedObject var appState: AppState
    @State private var correctionOriginal = ""
    @State private var correctionReplacement = ""
    @State private var showCorrectionForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Clear All") {
                    appState.clearHistory()
                }
                .disabled(appState.history.isEmpty)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

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

/// Window tab version
struct HistoryWindowContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HistoryContent(appState: appState)
    }
}

/// Sheet version with dismiss button (legacy menubar sheet)
struct HistoryView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcription History")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            HistoryContent(appState: appState)
        }
        .frame(width: 400, height: 500)
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
