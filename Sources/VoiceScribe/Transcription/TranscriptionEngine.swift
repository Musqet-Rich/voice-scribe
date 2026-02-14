import Foundation
import WhisperKit

/// Wraps WhisperKit for local speech-to-text transcription
final class TranscriptionEngine {
    private var whisperKit: WhisperKit?

    /// Download the specified model with progress updates
    func downloadModel(
        model: WhisperModel,
        modelDir: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let config = WhisperKitConfig(
            model: model.rawValue,
            downloadBase: modelDir,
            verbose: false,
            prewarm: true
        )

        // WhisperKit downloads and loads the model on init
        let kit = try await WhisperKit(config)

        // Note: WhisperKit doesn't expose granular download progress via its public API.
        // The model downloads during init. For a more granular progress UI, you'd need
        // to monitor the modelDir for file changes. For now, we go from 0 → 1.
        onProgress(1.0)

        self.whisperKit = kit
    }

    /// Transcribe an audio file and return the text
    func transcribe(audioURL: URL) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let results = try await kit.transcribe(audioPath: audioURL.path)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw TranscriptionError.emptyResult
        }

        return text
    }

    /// Try to load an already-downloaded model (no download, just init)
    func loadExistingModel(model: WhisperModel, modelDir: URL) async throws {
        // WhisperKit stores models at: downloadBase/models/argmaxinc/whisperkit-coreml/{model}/
        let modelFolder = modelDir
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.rawValue)

        print("[VoiceScribe] Looking for model at: \(modelFolder.path)")
        print("[VoiceScribe] Exists: \(FileManager.default.fileExists(atPath: modelFolder.path))")

        // List what's actually in the models dir for debugging
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) {
            print("[VoiceScribe] Contents of \(modelDir.path): \(contents)")
        }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelFolder.path) {
            print("[VoiceScribe] Model folder contents: \(contents)")
        }

        guard FileManager.default.fileExists(atPath: modelFolder.path) else {
            print("[VoiceScribe] Model folder not found, falling back to notDownloaded")
            throw TranscriptionError.modelNotLoaded
        }

        print("[VoiceScribe] Loading model from \(modelFolder.path)...")
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: modelDir,
            verbose: true,
            prewarm: true,
            load: true,
            download: false
        )
        self.whisperKit = try await WhisperKit(config)
        print("[VoiceScribe] Model loaded successfully!")
    }

    /// Check if a model is loaded and ready
    var isReady: Bool {
        whisperKit != nil
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded. Please download a model first."
        case .emptyResult:
            return "No speech was detected in the recording."
        }
    }
}
