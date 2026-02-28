import SwiftUI
import UniformTypeIdentifiers

/// Reusable corrections content — used in both sheet and window tab
struct CorrectionsContent: View {
    @ObservedObject var appState: AppState
    @State private var newOriginal = ""
    @State private var newCorrected = ""
    @State private var showImporter = false
    @State private var showExporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Import") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    showImporter = true
                }
                Button("Export") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    showExporter = true
                }
                .disabled(appState.corrections.isEmpty)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Add new correction
            HStack {
                TextField("Original", text: $newOriginal)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                TextField("Corrected", text: $newCorrected)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !newOriginal.isEmpty, !newCorrected.isEmpty else { return }
                    appState.addCorrection(original: newOriginal, corrected: newCorrected)
                    newOriginal = ""
                    newCorrected = ""
                }
                .disabled(newOriginal.isEmpty || newCorrected.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Corrections list
            if appState.corrections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.redaction")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No corrections defined")
                        .foregroundColor(.secondary)
                    Text("Add corrections to automatically fix common transcription errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.corrections) { correction in
                        HStack {
                            Text(correction.original)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            Text(correction.corrected)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) {
                                appState.removeCorrection(correction)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.json]
        ) { result in
            if case .success(let url) = result {
                if let data = try? Data(contentsOf: url) {
                    try? appState.correctionsManager.importData(data)
                    appState.corrections = appState.correctionsManager.corrections
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: JSONDocument(data: appState.correctionsManager.exportData() ?? Data()),
            contentType: .json,
            defaultFilename: "corrections.json"
        ) { _ in }
    }
}

/// Window tab version
struct CorrectionsWindowContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        CorrectionsContent(appState: appState)
    }
}

/// Sheet version with dismiss button (legacy menubar sheet)
struct CorrectionsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Corrections")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            CorrectionsContent(appState: appState)
        }
        .frame(width: 500, height: 400)
    }
}

/// Simple JSON document for file export
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
