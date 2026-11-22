import AVFoundation
import CoreAudio
import Foundation

/// Records everything the Mac plays (the other side of a Zoom/Meet/Teams/Slack call) to a file,
/// using a Core Audio process tap (macOS 14.2+). Needs the "System Audio Recording" permission,
/// which macOS prompts for on first use. No screen-recording permission required.
final class SystemAudioRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "voice-scribe.system-audio")

    func start(writingTo url: URL) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
        tapID = tap

        var streamDescription = try readProperty(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw SystemAudioError.failed("read tap format")
        }

        let outputDevice = try readProperty(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            AudioObjectID(kAudioObjectUnknown)
        )
        let outputUID = try readProperty(outputDevice, kAudioDevicePropertyDeviceUID, "" as CFString) as String

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VoiceScribe System Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "create aggregate device")
        aggregateID = agg

        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
        self.file = file

        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, agg, queue) { _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
            try? file.write(from: buffer)
        }, "create IO proc")
        procID = proc

        try check(AudioDeviceStart(agg, proc), "start device")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        queue.sync {}  // drain any in-flight writes
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        file = nil
    }

    // MARK: - Helpers

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw SystemAudioError.failed("\(what) (OSStatus \(status))") }
    }

    private func readProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        try check(status, "read property \(selector)")
        return value
    }
}

enum SystemAudioError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let what) = self { return "System audio capture failed: \(what)" }
        return nil
    }
}

/// Records the microphone at its native format to a file (for call recording)
final class MicFileRecorder {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?

    func start(writingTo url: URL, deviceUID: String? = nil) throws {
        let engine = AVAudioEngine()
        InputDevices.apply(uid: deviceUID, to: engine)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
        self.file = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil
    }
}
