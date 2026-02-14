import Foundation
import SwiftUI

/// Model download state
enum ModelState: Equatable {
    case checking
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case error(String)

    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.checking, .checking): return true
        case (.notDownloaded, .notDownloaded): return true
        case (.ready, .ready): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// Available WhisperKit models
enum WhisperModel: String, CaseIterable, Identifiable {
    case baseEn = "openai_whisper-base.en"
    case smallEn = "openai_whisper-small.en"
    case largeV3 = "openai_whisper-large-v3"
    case largeV3Turbo = "openai_whisper-large-v3_turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baseEn: return "Base (English) — ~150MB"
        case .smallEn: return "Small (English) — ~500MB"
        case .largeV3: return "Large v3 — ~3GB"
        case .largeV3Turbo: return "Large v3 Turbo — ~800MB"
        }
    }
}

/// Central app state — uses ObservableObject for MenuBarExtra compatibility
final class AppState: ObservableObject {
    // MARK: - Recording State
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var recordingStartTime: Date?

    // MARK: - Model State
    @Published var modelState: ModelState = .notDownloaded

    // MARK: - Data
    @Published var history: [TranscriptionItem] = []
    @Published var corrections: [Correction] = []

    // MARK: - Settings
    @Published var selectedModel: WhisperModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel") }
    }
    @Published var minimumHoldDuration: Double {
        didSet { UserDefaults.standard.set(minimumHoldDuration, forKey: "minimumHoldDuration") }
    }

    // MARK: - Managers
    let audioRecorder = AudioRecorder()
    let transcriptionEngine = TranscriptionEngine()
    let correctionsManager = CorrectionsManager()
    let hotkeyManager = HotkeyManager()
    let pasteManager = PasteManager()
    let tonePlayer = TonePlayer()

    // MARK: - Storage paths
    static let baseDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voice-scribe")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let historyFile = baseDir.appendingPathComponent("history.json")

    init() {
        // Load settings
        let modelRaw = UserDefaults.standard.string(forKey: "selectedModel") ?? WhisperModel.largeV3Turbo.rawValue
        self.selectedModel = WhisperModel(rawValue: modelRaw) ?? .largeV3Turbo
        self.minimumHoldDuration = UserDefaults.standard.double(forKey: "minimumHoldDuration")
        if minimumHoldDuration == 0 { minimumHoldDuration = 0.3 }

        // Load history
        loadHistory()

        // Load corrections
        corrections = correctionsManager.corrections

        // Setup hotkeys
        setupHotkeys()

        // Check if model is already downloaded
        Task { await checkModelState() }
    }

    // MARK: - Model Management

    @MainActor
    func checkModelState() {
        let modelDir = Self.baseDir.appendingPathComponent("models")
        // Try to load the model — WhisperKit knows its own directory structure
        modelState = .checking
        Task {
            do {
                try await transcriptionEngine.loadExistingModel(
                    model: selectedModel,
                    modelDir: modelDir
                )
                modelState = .ready
                setupHotkeys()
            } catch {
                // Model not found or failed to load — show download view
                print("[VoiceScribe] checkModelState failed: \(error)")
                modelState = .notDownloaded
            }
        }
    }

    @MainActor
    func downloadModel() async {
        modelState = .downloading(progress: 0)
        do {
            try await transcriptionEngine.downloadModel(
                model: selectedModel,
                modelDir: Self.baseDir.appendingPathComponent("models")
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.modelState = .downloading(progress: progress)
                }
            }
            modelState = .ready
        } catch {
            modelState = .error(error.localizedDescription)
        }
    }

    // MARK: - Recording

    @MainActor
    func startRecording() {
        guard !isRecording, modelState == .ready else { return }
        tonePlayer.playStartTone()
        audioRecorder.startRecording()
        isRecording = true
        recordingStartTime = Date()
    }

    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        tonePlayer.playStopTone()

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

        // Ignore very short recordings (accidental taps)
        guard duration >= minimumHoldDuration else { return }

        guard let audioURL = audioRecorder.stopRecording() else { return }

        isTranscribing = true
        Task {
            do {
                let rawText = try await transcriptionEngine.transcribe(audioURL: audioURL)
                let correctedText = correctionsManager.apply(rawText)

                let item = TranscriptionItem(
                    text: rawText,
                    correctedText: correctedText,
                    duration: duration
                )

                await MainActor.run {
                    history.insert(item, at: 0)
                    saveHistory()
                    isTranscribing = false
                }

                // Paste the corrected text
                pasteManager.paste(correctedText)

                // Clean up temp file
                try? FileManager.default.removeItem(at: audioURL)
            } catch {
                await MainActor.run {
                    isTranscribing = false
                }
                print("Transcription error: \(error)")
            }
        }
    }

    @MainActor
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.onHoldStart = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onHoldEnd = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotkeyManager.registerDefaults()
    }

    // MARK: - History Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: Self.historyFile.path) else { return }
        do {
            let data = try Data(contentsOf: Self.historyFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode([TranscriptionItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(history)
            try data.write(to: Self.historyFile)
        } catch {
            print("Failed to save history: \(error)")
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

    func removeCorrection(_ correction: Correction) {
        correctionsManager.remove(original: correction.original)
        corrections = correctionsManager.corrections
    }

    func reloadCorrections() {
        correctionsManager.load()
        corrections = correctionsManager.corrections
    }
}
