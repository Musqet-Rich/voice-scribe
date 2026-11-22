import AppKit
import Foundation
import SwiftUI

/// Model download/load state
enum ModelState: Equatable {
    case checking
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case error(String)
}

/// Central app state — uses ObservableObject for MenuBarExtra compatibility
@MainActor
final class AppState: ObservableObject {
    // MARK: - Dictation State
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingStartTime: Date?
    @Published var lastError: String?

    // MARK: - Call State
    @Published var isCallRecording = false
    @Published var callStartTime: Date?
    @Published var calls: [CallRecord] = []
    @Published var callStatus: [URL: String] = [:]

    // MARK: - Model State
    @Published var modelState: ModelState = .checking

    // MARK: - Data
    @Published var history: [TranscriptionItem] = []
    @Published var corrections: [Correction] = []

    // MARK: - Settings
    @Published var selectedModel: SpeechModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "speechModel")
            if oldValue != selectedModel { Task { await loadModel() } }
        }
    }
    @Published var minimumHoldDuration: Double {
        didSet { UserDefaults.standard.set(minimumHoldDuration, forKey: "minimumHoldDuration") }
    }
    @Published var polishEnabled: Bool {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "polishEnabled") }
    }
    @Published var summariseCalls: Bool {
        didSet { UserDefaults.standard.set(summariseCalls, forKey: "summariseCalls") }
    }
    @Published var shortcuts: [ShortcutAction: [Shortcut]] {
        didSet {
            for action in ShortcutAction.allCases {
                if let data = try? JSONEncoder().encode(shortcuts[action] ?? []) {
                    UserDefaults.standard.set(data, forKey: action.storageKey)
                }
            }
            hotkeyManager.register(shortcuts)
        }
    }
    /// Selected microphone UID; empty = follow the macOS default input
    @Published var inputDeviceUID: String {
        didSet { UserDefaults.standard.set(inputDeviceUID, forKey: "inputDeviceUID") }
    }
    @Published var inputDevices: [InputDevice] = []

    /// Name of the mic that will actually be used
    var activeMicName: String {
        if !inputDeviceUID.isEmpty, let d = inputDevices.first(where: { $0.uid == inputDeviceUID }) {
            return d.name
        }
        return InputDevices.defaultInputName() ?? "System default"
    }

    /// Selected UID if that device is connected, otherwise nil (use the default)
    private var effectiveDeviceUID: String? {
        inputDevices.contains { $0.uid == inputDeviceUID } ? inputDeviceUID : nil
    }

    func refreshInputDevices() {
        inputDevices = InputDevices.all()
    }

    @Published var soundCues: Bool {
        didSet { UserDefaults.standard.set(soundCues, forKey: "soundCues") }
    }
    @Published var showPill: Bool {
        didSet { UserDefaults.standard.set(showPill, forKey: "showPill") }
    }
    let pill = PillController()

    // MARK: - Learning corrections from edits
    @Published var learnFromEdits: Bool {
        didSet { UserDefaults.standard.set(learnFromEdits, forKey: "learnFromEdits") }
    }
    private let editWatcher = EditWatcher()
    private let toast = CallPromptController(verticalOffset: 76)

    // MARK: - Call detection
    /// Per-app behaviour when it starts using the mic (WatchedApp.id → mode)
    @Published var callModes: [String: CallAppMode] {
        didSet {
            if let data = try? JSONEncoder().encode(callModes) {
                UserDefaults.standard.set(data, forKey: "callModes")
            }
        }
    }
    private let callDetector = CallDetector()
    private let callPrompt = CallPromptController()
    /// The detected app whose call we are recording (auto-stops when it releases the mic)
    private var recordingDetectedApp: String?

    func callMode(for app: WatchedApp) -> CallAppMode { callModes[app.id] ?? .ask }

    @Published var keepCallAudio: Bool {
        didSet { UserDefaults.standard.set(keepCallAudio, forKey: "keepCallAudio") }
    }

    // MARK: - Managers
    let audioRecorder = AudioRecorder()
    let transcriptionEngine = TranscriptionEngine()
    let correctionsManager = CorrectionsManager()
    let hotkeyManager = HotkeyManager()
    let pasteManager = PasteManager()
    let tonePlayer = TonePlayer()
    private let micFileRecorder = MicFileRecorder()
    private let systemAudioRecorder = SystemAudioRecorder()
    private lazy var callTranscriber = CallTranscriber(engine: transcriptionEngine)
    private var currentCall: CallRecord?

    // MARK: - Storage paths
    static let baseDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".voice-scribe")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static let historyFile = baseDir.appendingPathComponent("history.json")
    static let callsDir: URL = {
        let url = baseDir.appendingPathComponent("calls")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "minimumHoldDuration": 0.3,
            "polishEnabled": false,
            "summariseCalls": true,
            "keepCallAudio": true,
            "soundCues": false,
            "showPill": true,
            "learnFromEdits": true,
        ])
        selectedModel = SpeechModel(rawValue: defaults.string(forKey: "speechModel") ?? "") ?? .bark3Clean
        minimumHoldDuration = defaults.double(forKey: "minimumHoldDuration")
        polishEnabled = defaults.bool(forKey: "polishEnabled")
        summariseCalls = defaults.bool(forKey: "summariseCalls")
        keepCallAudio = defaults.bool(forKey: "keepCallAudio")
        soundCues = defaults.bool(forKey: "soundCues")
        showPill = defaults.bool(forKey: "showPill")
        learnFromEdits = defaults.bool(forKey: "learnFromEdits")
        callModes = defaults.data(forKey: "callModes")
            .flatMap { try? JSONDecoder().decode([String: CallAppMode].self, from: $0) } ?? [:]
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        inputDevices = InputDevices.all()
        var loaded: [ShortcutAction: [Shortcut]] = [:]
        for action in ShortcutAction.allCases {
            loaded[action] = defaults.data(forKey: action.storageKey)
                .flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) } ?? action.defaults
        }
        shortcuts = loaded

        loadHistory()
        audioRecorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.pill.setLevel(level) }
        }
        corrections = correctionsManager.corrections
        reloadCalls()
        setupHotkeys()
        setupCallDetection()
        editWatcher.onEdits = { [weak self] edits in
            MainActor.assumeIsolated { self?.considerEdits(edits) }
        }

        Task {
            _ = await AudioRecorder.requestPermission()
            _ = HotkeyManager.ensureAccessibility()
            if polishEnabled, TextPolisher.engine == .ollama {
                TextPolisher.warmUp(model: TextPolisher.polishModel)
            }
            if transcriptionEngine.isDownloaded(selectedModel) {
                await loadModel()
            } else {
                modelState = .notDownloaded
            }
        }
    }

    // MARK: - Model Management

    /// Download (if needed) and load the selected model
    func loadModel() async {
        let model = selectedModel
        modelState = transcriptionEngine.isDownloaded(model) ? .checking : .downloading(progress: 0)
        do {
            try await transcriptionEngine.load(model) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .downloading = self.modelState else { return }
                    self.modelState = .downloading(progress: progress)
                }
            }
            modelState = .ready
        } catch {
            modelState = .error(error.localizedDescription)
        }
    }

    func downloadModel() async { await loadModel() }

    // MARK: - Dictation

    func startRecording() {
        guard !isRecording, !isTranscribing, modelState == .ready else { return }
        do {
            editWatcher.finish()
            refreshInputDevices()
            try audioRecorder.startRecording(deviceUID: effectiveDeviceUID)
            if soundCues { tonePlayer.playStartTone() }
            if showPill { pill.show(.listening) }
            isRecording = true
            recordingStartTime = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Discard the current dictation (e.g. Fn was used as a shortcut modifier)
    func cancelRecording() {
        guard isRecording else { return }
        _ = audioRecorder.stopRecording()
        isRecording = false
        pill.hide()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        let samples = audioRecorder.stopRecording()
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        guard duration >= minimumHoldDuration else {
            pill.hide()
            return
        }
        if soundCues { tonePlayer.playStopTone() }
        if showPill { pill.show(.transcribing) }

        isTranscribing = true
        let polish = polishEnabled
        let vocabulary = correctionsManager.corrections.map(\.corrected)
        Task {
            defer {
                isTranscribing = false
                pill.hide()
            }
            do {
                let raw = try await transcriptionEngine.transcribe(samples: samples)
                guard !raw.isEmpty else { throw TranscriptionError.emptyResult }
                var text = correctionsManager.apply(raw)
                if polish {
                    text = correctionsManager.apply(await TextPolisher.polishDictation(text, vocabulary: vocabulary))
                }
                pasteManager.paste(text)
                if learnFromEdits { editWatcher.watch(pasted: text) }
                history.insert(TranscriptionItem(text: raw, correctedText: text, duration: duration), at: 0)
                saveHistory()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    // MARK: - Calls

    func toggleCallRecording() {
        isCallRecording ? stopCall() : startCall()
    }

    func startCall(label: String? = nil) {
        guard !isCallRecording else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        var name = formatter.string(from: Date())
        if let label { name += " \(label)" }
        let folder = Self.callsDir.appendingPathComponent(name)
        let call = CallRecord(folder: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            refreshInputDevices()
            try micFileRecorder.start(writingTo: call.micURL, deviceUID: effectiveDeviceUID)
            do {
                try systemAudioRecorder.start(writingTo: call.systemURL)
            } catch {
                micFileRecorder.stop()
                throw error
            }
            currentCall = call
            isCallRecording = true
            callStartTime = Date()
            if soundCues { tonePlayer.playStartTone() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopCall() {
        guard isCallRecording, let call = currentCall else { return }
        recordingDetectedApp = nil
        micFileRecorder.stop()
        systemAudioRecorder.stop()
        isCallRecording = false
        callStartTime = nil
        currentCall = nil
        if soundCues { tonePlayer.playStopTone() }
        reloadCalls()
        transcribeCall(call)
    }

    func transcribeCall(_ call: CallRecord) {
        guard modelState == .ready else {
            callStatus[call.id] = "Model not loaded"
            return
        }
        callStatus[call.id] = "Queued…"
        let summarise = summariseCalls
        let keepAudio = keepCallAudio
        Task {
            do {
                try await callTranscriber.transcribe(call, summarise: summarise) { status in
                    Task { @MainActor in self.callStatus[call.id] = status }
                }
                if !keepAudio {
                    try? FileManager.default.removeItem(at: call.micURL)
                    try? FileManager.default.removeItem(at: call.systemURL)
                }
                callStatus[call.id] = nil
                reloadCalls()
                NSWorkspace.shared.open(call.transcriptURL)
            } catch {
                callStatus[call.id] = "Failed: \(error.localizedDescription)"
            }
        }
    }

    func reloadCalls() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.callsDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        calls = urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(CallRecord.init(folder:))
            .sorted { $0.name > $1.name }
    }

    // MARK: - Call detection

    private func setupCallDetection() {
        callDetector.onCallStarted = { [weak self] app in
            MainActor.assumeIsolated { self?.detectedCallStarted(app) }
        }
        callDetector.onCallEnded = { [weak self] app in
            MainActor.assumeIsolated { self?.detectedCallEnded(app) }
        }
        callDetector.start()
    }

    private func detectedCallStarted(_ app: WatchedApp) {
        guard !isCallRecording, modelState == .ready else { return }
        switch callMode(for: app) {
        case .off:
            return
        case .auto:
            startDetectedCall(app)
            if isCallRecording {
                callPrompt.notifyAutoRecording(app) { [weak self] in self?.stopCall() }
            }
        case .ask:
            callPrompt.ask(app, onRecord: { [weak self] in
                self?.startDetectedCall(app)
            }, onIgnore: {})
        }
    }

    private func detectedCallEnded(_ app: WatchedApp) {
        if callPrompt.appID == app.id { callPrompt.dismiss() }
        if isCallRecording, recordingDetectedApp == app.id { stopCall() }
    }

    private func startDetectedCall(_ app: WatchedApp) {
        guard !isCallRecording else { return }
        startCall(label: app.name.components(separatedBy: " (").first)
        if isCallRecording { recordingDetectedApp = app.id }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.onHoldStart = { [weak self] in Task { @MainActor in self?.startRecording() } }
        hotkeyManager.onHoldEnd = { [weak self] in Task { @MainActor in self?.stopRecording() } }
        hotkeyManager.onHoldCancel = { [weak self] in Task { @MainActor in self?.cancelRecording() } }
        hotkeyManager.onToggle = { [weak self] in Task { @MainActor in self?.toggleRecording() } }
        hotkeyManager.onCallToggle = { [weak self] in Task { @MainActor in self?.toggleCallRecording() } }
        hotkeyManager.register(shortcuts)
    }

    func addShortcut(_ shortcut: Shortcut, to action: ShortcutAction) {
        var updated = shortcuts
        // A key can only do one thing
        for a in ShortcutAction.allCases { updated[a]?.removeAll { $0 == shortcut } }
        updated[action, default: []].append(shortcut)
        shortcuts = updated
    }

    func removeShortcut(_ shortcut: Shortcut, from action: ShortcutAction) {
        shortcuts[action]?.removeAll { $0 == shortcut }
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaults) })
    }

    // MARK: - History Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = (try? decoder.decode([TranscriptionItem].self, from: data)) ?? []
    }

    func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(history) {
            try? data.write(to: Self.historyFile)
        }
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Corrections

    func addCorrection(original: String, corrected: String) {
        correctionsManager.add(original: original, corrected: corrected)
        corrections = correctionsManager.corrections
    }

    /// Decide which observed edits are recognition errors and learn them
    private func considerEdits(_ edits: [ObservedEdit]) {
        guard learnFromEdits else { return }
        for edit in edits {
            let existing = correctionsManager.corrections.first {
                $0.original.caseInsensitiveCompare(edit.heard) == .orderedSame
            }
            if existing?.corrected == edit.fixed { continue }
            Task {
                let verdict = await TextPolisher.judgeEdit(
                    heard: edit.heard, fixed: edit.fixed, context: edit.context,
                    vocabulary: correctionsManager.corrections.map(\.corrected)
                )
                let learn: Bool
                switch verdict {
                case .mishearing: learn = true
                case .rewrite: learn = false
                case .unknown: learn = Self.looksLikeMishearing(edit.heard, edit.fixed)  // no AI: similarity only
                }
                guard learn else { return }
                addCorrection(original: edit.heard, corrected: edit.fixed)
                toast.show(
                    icon: "text.badge.checkmark", colour: .green,
                    title: "Added: \(edit.heard) → \(edit.fixed)",
                    subtitle: "Learnt from your edit",
                    primary: ("Undo", { [weak self] in
                        guard let self else { return }
                        self.correctionsManager.remove(original: edit.heard)
                        if let existing { self.correctionsManager.add(original: existing.original, corrected: existing.corrected) }
                        self.corrections = self.correctionsManager.corrections
                    }),
                    secondary: nil,
                    autoDismissAfter: 6
                )
            }
        }
    }

    /// Fallback when no AI is available: case-only change, or the words are spelt similarly
    nonisolated static func looksLikeMishearing(_ a: String, _ b: String) -> Bool {
        if a.caseInsensitiveCompare(b) == .orderedSame { return true }
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        var row = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in stride(from: 1, through: y.count, by: 1) {
                let tmp = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (x[i - 1] == y[j - 1] ? 0 : 1))
                prev = tmp
            }
        }
        let distance = row[y.count]
        return Double(distance) / Double(max(x.count, y.count, 1)) <= 0.5
    }

    func removeCorrection(_ correction: Correction) {
        correctionsManager.remove(original: correction.original)
        corrections = correctionsManager.corrections
    }

    func reloadCorrections() {
        correctionsManager.load()
        corrections = correctionsManager.corrections
    }
}
