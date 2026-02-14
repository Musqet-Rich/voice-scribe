import AVFoundation
import Foundation

/// Records microphone audio to a temporary WAV file using AVAudioEngine
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    /// Start recording from the microphone
    func startRecording() {
        // Request microphone permission if needed
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    Task { @MainActor in self.startRecording() }
                }
            }
            return
        default:
            print("Microphone access denied")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono (what WhisperKit expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            print("Failed to create target audio format")
            return
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        self.tempFileURL = tempFile

        do {
            audioFile = try AVAudioFile(
                forWriting: tempFile,
                settings: targetFormat.settings
            )
        } catch {
            print("Failed to create audio file: \(error)")
            return
        }

        // Install tap with format conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let audioFile = self.audioFile else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil {
                do {
                    try audioFile.write(from: convertedBuffer)
                } catch {
                    print("Failed to write audio buffer: \(error)")
                }
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    /// Stop recording and return the URL of the recorded audio file
    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        return tempFileURL
    }
}
