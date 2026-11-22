import AppKit
import SwiftUI

/// Lists recorded calls and their transcripts
struct CallsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: CallRecord?

    var body: some View {
        HSplitView {
            List(appState.calls, selection: $selection) { call in
                VStack(alignment: .leading, spacing: 2) {
                    Text(call.name)
                    if let status = appState.callStatus[call.id] {
                        Text(status).font(.caption).foregroundColor(.orange)
                    } else if !call.hasTranscript {
                        Text("No transcript").font(.caption).foregroundColor(.secondary)
                    }
                }
                .tag(call)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([call.folder]) }
                    Button("Re-transcribe") { appState.transcribeCall(call) }
                }
            }
            .frame(minWidth: 160, idealWidth: 180)

            Group {
                if let call = selection {
                    detail(call)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "phone")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(appState.calls.isEmpty
                             ? "No calls yet. Press ⌃⌥⌘R or use the menu bar to record one."
                             : "Select a call")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .toolbar {
            Button(appState.isCallRecording ? "Stop Call Recording" : "Record Call") {
                appState.toggleCallRecording()
            }
        }
        .onAppear { appState.reloadCalls() }
    }

    @ViewBuilder
    private func detail(_ call: CallRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(call.name).font(.headline)
                Spacer()
                Button("Copy") {
                    if let text = try? String(contentsOf: call.transcriptURL, encoding: .utf8) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                .disabled(!call.hasTranscript)
                Button("Open") { NSWorkspace.shared.open(call.transcriptURL) }
                    .disabled(!call.hasTranscript)
                Button("Re-transcribe") { appState.transcribeCall(call) }
                    .disabled(appState.callStatus[call.id] != nil)
            }
            ScrollView {
                Text((try? String(contentsOf: call.transcriptURL, encoding: .utf8)) ?? "Not transcribed yet.")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body)
            }
        }
        .padding()
    }
}
