import SwiftUI

/// Reusable settings form content — used in both the sheet and window tab
struct SettingsFormContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            ShortcutsSection(appState: appState)

            // MARK: - Recording Section
            Section("Microphone") {
                Picker("Microphone:", selection: $appState.inputDeviceUID) {
                    Text("System default (\(InputDevices.defaultInputName() ?? "unknown"))").tag("")
                    ForEach(appState.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if !appState.inputDeviceUID.isEmpty,
                       !appState.inputDevices.contains(where: { $0.uid == appState.inputDeviceUID }) {
                        Text("Saved mic (not connected, using default)").tag(appState.inputDeviceUID)
                    }
                }
                .onAppear { appState.refreshInputDevices() }
                Text("If the chosen mic is unplugged, the macOS default is used until it's back.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Dictation") {
                Toggle("Show listening pill at the bottom of the screen", isOn: $appState.showPill)
                Toggle("Play start/stop sounds", isOn: $appState.soundCues)
                Toggle("Learn corrections from my edits", isOn: $appState.learnFromEdits)
                Text("After pasting, Voice Scribe watches the text box for a minute. If you fix a misheard word, it's added to Corrections (with Undo). Your local AI model judges whether an edit is a mishearing or a change of mind.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Min hold duration:")
                    Slider(value: $appState.minimumHoldDuration, in: 0.1...1.0, step: 0.1)
                    Text("\(appState.minimumHoldDuration, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            // MARK: - Calls Section
            Section("Calls") {
                Toggle("Keep call audio after transcribing", isOn: $appState.keepCallAudio)
                Text("Records your mic and the Mac's audio output as separate tracks. Use headphones, otherwise the other side also gets picked up by your mic.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            CallDetectionSection(appState: appState)

            AISection(appState: appState)

            // MARK: - Model Section
            Section("Model") {
                Picker("Speech model:", selection: $appState.selectedModel) {
                    ForEach(SpeechModel.allCases) { model in
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

                Text("Models download once, then run fully offline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: - About Section
            Section("About") {
                Text("Voice Scribe")
                    .fontWeight(.semibold)
                Text("Local speech-to-text: Parakeet via FluidAudio, on the Neural Engine")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Data stored in ~/.voice-scribe/")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Window tab version — no dismiss button, no frame constraints
struct SettingsWindowContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsFormContent(appState: appState)
    }
}

/// Sheet version with dismiss button (legacy menubar sheet)
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

            SettingsFormContent(appState: appState)
        }
        .frame(width: 450, height: 500)
    }
}

/// Local LLM settings: engine, models, and what to use it for
struct AISection: View {
    @ObservedObject var appState: AppState
    @AppStorage("aiEngine") private var engine: AIEngine = .off
    @AppStorage("ollamaPolishModel") private var polishModel = ""
    @AppStorage("ollamaSummaryModel") private var summaryModel = ""
    @State private var models: [String] = []
    @State private var ollamaChecked = false

    var body: some View {
        Section("AI (local)") {
            Picker("Engine:", selection: $engine) {
                ForEach(AIEngine.allCases) { e in
                    Text(e.displayName).tag(e)
                }
            }

            if engine == .apple, !TextPolisher.appleAvailable {
                Text("Apple Intelligence isn't enabled on this Mac.")
                    .font(.caption).foregroundColor(.orange)
            }

            if engine == .ollama {
                if ollamaChecked && models.isEmpty {
                    Text("Ollama isn't running. Start it (ollama serve or the Ollama app), then reopen Settings.")
                        .font(.caption).foregroundColor(.orange)
                } else {
                    Picker("Polish model:", selection: $polishModel) {
                        Text("None").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Summary model:", selection: $summaryModel) {
                        Text("None").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    Text("Polish runs after every dictation, so use a small, fast model (e.g. ollama pull qwen3:4b). Summaries run once per call, so a big model is fine.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if engine != .off {
                Toggle("Polish dictation (punctuation, self-corrections, British spelling)", isOn: $appState.polishEnabled)
                    .disabled(!TextPolisher.canPolish)
                Toggle("Summarise calls (summary, decisions, action items)", isOn: $appState.summariseCalls)
                    .disabled(!TextPolisher.canSummarise)
            }
        }
        .task(id: engine) {
            guard engine == .ollama else { return }
            models = await TextPolisher.ollamaModels()
            ollamaChecked = true
        }
        .onChange(of: polishModel) { _, m in TextPolisher.warmUp(model: m) }
    }
}

/// Per-app call detection settings, plus a live view of what's using the mic
struct CallDetectionSection: View {
    @ObservedObject var appState: AppState
    @State private var usingMic: [String] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Call detection") {
            Text("When one of these starts using the microphone, Voice Scribe can ask to record or record automatically. Recordings it starts stop when the app releases the mic.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(WatchedApp.all.filter { !$0.isBrowser }) { app in row(app) }

            Text("Browsers")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            ForEach(WatchedApp.all.filter(\.isBrowser)) { app in row(app) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Using the microphone right now")
                    .font(.subheadline.weight(.semibold))
                if usingMic.isEmpty {
                    Text("Nothing").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(usingMic, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
            .padding(.top, 4)
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func row(_ app: WatchedApp) -> some View {
        Picker(app.name, selection: Binding(
            get: { appState.callMode(for: app) },
            set: { appState.callModes[app.id] = $0 }
        )) {
            ForEach(CallAppMode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func refresh() {
        let own = Bundle.main.bundleIdentifier ?? "com.monomi.voice-scribe"
        usingMic = Array(Set(CallDetector.bundleIDsCapturingInput().filter { !$0.hasPrefix(own) })).sorted().map { id in
            if let app = WatchedApp.matching(bundleID: id) { return "\(app.name)  (\(id))" }
            return id
        }
    }
}
