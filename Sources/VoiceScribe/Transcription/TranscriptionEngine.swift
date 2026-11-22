import FluidAudio
import Foundation

/// Speech models available through FluidAudio (all Parakeet-family, run on the Neural Engine)
enum SpeechModel: String, CaseIterable, Identifiable {
    case bark3Clean
    case bark3
    case ultra
    case v2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bark3Clean: return "Bark 3.0 Clean (English, drops fillers) ~410MB"
        case .bark3: return "Bark 3.0 (English, verbatim) ~400MB"
        case .ultra: return "Parakeet Ultra (25 languages) ~600MB"
        case .v2: return "Parakeet v2 (English) ~600MB"
        }
    }

    var version: AsrModelVersion {
        switch self {
        case .bark3Clean: return .bark3Clean
        case .bark3: return .bark3
        case .ultra: return .ultra
        case .v2: return .v2
        }
    }
}

/// Timed text returned by the engine
struct TimedText {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Wraps FluidAudio's Parakeet ASR. The model stays loaded in memory between dictations.
final class TranscriptionEngine {
    static let sampleRate = 16_000

    private var asr: AsrManager?
    private(set) var loadedModel: SpeechModel?

    var isReady: Bool { asr != nil }

    func isDownloaded(_ model: SpeechModel) -> Bool {
        AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: model.version),
            version: model.version
        )
    }

    /// Download (if needed) and load a model, then warm it up so the first dictation is fast
    func load(_ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(version: model.version) { progress in
            onProgress(progress.fractionCompleted)
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asr = manager
        loadedModel = model

        // Warm-up pass: compiles/caches the ANE graph
        _ = try? await transcribe(samples: [Float](repeating: 0, count: Self.sampleRate))
    }

    /// Transcribe 16kHz mono samples
    func transcribe(samples: [Float]) async throws -> String {
        try await transcribeDetailed(samples: samples).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribeDetailed(samples: [Float]) async throws -> ASRResult {
        guard let asr else { throw TranscriptionError.modelNotLoaded }
        var padded = samples
        // Very short clips can fail the encoder; pad to one second of silence
        if padded.count < Self.sampleRate {
            padded.append(contentsOf: [Float](repeating: 0, count: Self.sampleRate - padded.count))
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(padded, decoderState: &state)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech model is not loaded."
        case .emptyResult:
            return "No speech was detected in the recording."
        }
    }
}
