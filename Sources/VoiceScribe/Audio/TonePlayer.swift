import AVFoundation
import Foundation

/// Plays simple feedback tones for recording start/stop
final class TonePlayer {
    /// Play a 440Hz tone for 100ms (recording started)
    func playStartTone() {
        playTone(frequency: 440, duration: 0.1)
    }

    /// Play a 660Hz tone for 100ms (recording stopped)
    func playStopTone() {
        playTone(frequency: 660, duration: 0.1)
    }

    private func playTone(frequency: Double, duration: Double) {
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * duration)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData?[0] else { return }

        for i in 0..<frameCount {
            let value = sin(2.0 * .pi * frequency * Double(i) / sampleRate)
            // Apply a small fade in/out to avoid clicks
            let envelope: Double
            let fadeFrames = Int(sampleRate * 0.005) // 5ms fade
            if i < fadeFrames {
                envelope = Double(i) / Double(fadeFrames)
            } else if i > frameCount - fadeFrames {
                envelope = Double(frameCount - i) / Double(fadeFrames)
            } else {
                envelope = 1.0
            }
            channelData[i] = Float(value * 0.3 * envelope) // 0.3 volume
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            playerNode.scheduleBuffer(buffer) {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                    engine.stop()
                }
            }
        } catch {
            print("Failed to play tone: \(error)")
        }
    }
}
