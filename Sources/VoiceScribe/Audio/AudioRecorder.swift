import AVFoundation
import Foundation

/// Records microphone audio into memory as 16kHz mono Float samples
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var samples: [Float] = []
    private let lock = NSLock()

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Start recording from the default input device
    func startRecording(deviceUID: String? = nil) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.permissionDenied
        }

        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let engine = AVAudioEngine()
        InputDevices.apply(uid: deviceUID, to: engine)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.formatUnavailable
        }
        // Stereo receivers (e.g. DJI Mic with one transmitter per channel): mix down rather than drop channel 2
        converter.downmix = true

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            ) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    /// Stop recording and return the captured samples
    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        return lock.withLock { samples }
    }
}

enum RecorderError: LocalizedError {
    case permissionDenied
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .formatUnavailable: return "Could not set up the audio format."
        }
    }
}
