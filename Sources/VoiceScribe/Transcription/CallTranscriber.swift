import FluidAudio
import Foundation

/// A recorded call on disk: ~/.voice-scribe/calls/<yyyy-MM-dd HHmm>/
struct CallRecord: Identifiable, Hashable {
    let folder: URL
    var id: URL { folder }
    var name: String { folder.lastPathComponent }
    var micURL: URL { folder.appendingPathComponent("mic.caf") }
    var systemURL: URL { folder.appendingPathComponent("system.caf") }
    var transcriptURL: URL { folder.appendingPathComponent("transcript.md") }
    var hasTranscript: Bool { FileManager.default.fileExists(atPath: transcriptURL.path) }
}

/// Turns the two call tracks into a speaker-labelled transcript.
/// - Mic track → "Me" (split into utterances with VAD)
/// - System track → "Speaker 1/2/…" (split with offline speaker diarisation)
final class CallTranscriber {
    private let engine: TranscriptionEngine
    private var vad: VadManager?
    private var diarizer: OfflineDiarizerManager?

    init(engine: TranscriptionEngine) {
        self.engine = engine
    }

    private struct Line {
        let speaker: String
        let start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    func transcribe(_ call: CallRecord, summarise: Bool, onStatus: @escaping (String) -> Void) async throws {
        let converter = AudioConverter()
        let sr = Double(TranscriptionEngine.sampleRate)
        var lines: [Line] = []

        if FileManager.default.fileExists(atPath: call.micURL.path) {
            onStatus("Transcribing your side…")
            let mic = try converter.resampleAudioFile(call.micURL)
            let vad = try await loadVad()
            for seg in try await vad.segmentSpeech(mic) {
                if let line = try await transcribeSlice(mic, seg.startTime, seg.endTime, sr, speaker: "Me") {
                    lines.append(line)
                }
            }
        }

        if FileManager.default.fileExists(atPath: call.systemURL.path) {
            let system = try converter.resampleAudioFile(call.systemURL)
            onStatus("Identifying speakers…")
            var spans: [(speaker: String, start: Double, end: Double)] = []
            do {
                let diarizer = try await loadDiarizer()
                let result = try await diarizer.process(audio: system)
                var names: [String: String] = [:]
                for seg in result.segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
                    let name = names[seg.speakerId] ?? {
                        let n = "Speaker \(names.count + 1)"
                        names[seg.speakerId] = n
                        return n
                    }()
                    // Merge consecutive segments from the same speaker separated by short gaps
                    if let last = spans.last, last.speaker == name, Double(seg.startTimeSeconds) - last.end < 1.0 {
                        spans[spans.count - 1].end = Double(seg.endTimeSeconds)
                    } else {
                        spans.append((name, Double(seg.startTimeSeconds), Double(seg.endTimeSeconds)))
                    }
                }
            } catch {
                print("[VoiceScribe] Diarisation failed, falling back to VAD: \(error)")
                let vad = try await loadVad()
                spans = try await vad.segmentSpeech(system).map { ("Them", $0.startTime, $0.endTime) }
            }

            onStatus("Transcribing other side…")
            for span in spans {
                if let line = try await transcribeSlice(system, span.start, span.end, sr, speaker: span.speaker) {
                    lines.append(line)
                }
            }
        }

        lines.sort { $0.start < $1.start }
        let body = render(lines)

        var markdown = "# Call \(call.name)\n\n"
        if summarise, TextPolisher.canSummarise, !lines.isEmpty {
            onStatus("Summarising…")
            if let summary = await TextPolisher.summariseCall(body) {
                markdown += "## Summary\n\n\(summary)\n\n"
            }
        }
        markdown += "## Transcript\n\n" + body
        try markdown.write(to: call.transcriptURL, atomically: true, encoding: .utf8)
        onStatus("Done")
    }

    private func transcribeSlice(_ samples: [Float], _ start: Double, _ end: Double, _ sr: Double, speaker: String) async throws -> Line? {
        let from = max(0, Int(start * sr))
        let to = min(samples.count, Int(end * sr))
        guard to - from > Int(0.3 * sr) else { return nil }
        let text = try await engine.transcribe(samples: Array(samples[from..<to]))
        guard !text.isEmpty else { return nil }
        return Line(speaker: speaker, start: start, end: end, text: text)
    }

    /// Collapse consecutive lines from the same speaker into one paragraph
    private func render(_ lines: [Line]) -> String {
        var merged: [Line] = []
        for line in lines {
            if var last = merged.last, last.speaker == line.speaker, line.start - last.end < 3 {
                last.text += " " + line.text
                last.end = line.end
                merged[merged.count - 1] = last
            } else {
                merged.append(line)
            }
        }
        return merged.map { "**[\(timestamp($0.start))] \($0.speaker):** \($0.text)\n" }.joined(separator: "\n")
    }

    private func timestamp(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func loadVad() async throws -> VadManager {
        if let vad { return vad }
        let v = try await VadManager()
        vad = v
        return v
    }

    private func loadDiarizer() async throws -> OfflineDiarizerManager {
        if let diarizer { return diarizer }
        let d = OfflineDiarizerManager(config: .default)
        try await d.prepareModels()
        diarizer = d
        return d
    }
}
