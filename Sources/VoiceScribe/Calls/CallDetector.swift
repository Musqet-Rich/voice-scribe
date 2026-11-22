import AppKit
import CoreAudio
import Foundation

/// What to do when an app starts using the microphone
enum CallAppMode: String, CaseIterable, Identifiable, Codable {
    case off, ask, auto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .ask: return "Ask"
        case .auto: return "Auto-record"
        }
    }
}

/// An app Voice Scribe watches for microphone use
struct WatchedApp: Identifiable, Hashable {
    let id: String              // stable key for settings
    let name: String
    let isBrowser: Bool
    /// Bundle ID prefixes of the processes that capture audio for this app
    /// (browsers capture in helper processes, e.g. com.google.Chrome.helper)
    let bundlePrefixes: [String]

    static let all: [WatchedApp] = [
        WatchedApp(id: "zoom", name: "Zoom", isBrowser: false, bundlePrefixes: ["us.zoom."]),
        WatchedApp(id: "teams", name: "Microsoft Teams", isBrowser: false, bundlePrefixes: ["com.microsoft.teams"]),
        WatchedApp(id: "slack", name: "Slack (huddles & calls)", isBrowser: false, bundlePrefixes: ["com.tinyspeck.slackmacgap"]),
        WatchedApp(id: "facetime", name: "FaceTime", isBrowser: false, bundlePrefixes: ["com.apple.FaceTime"]),
        WatchedApp(id: "webex", name: "Webex", isBrowser: false, bundlePrefixes: ["Cisco-Systems.Spark", "com.cisco.webex"]),
        WatchedApp(id: "discord", name: "Discord", isBrowser: false, bundlePrefixes: ["com.hnc.Discord"]),
        WatchedApp(id: "whatsapp", name: "WhatsApp", isBrowser: false, bundlePrefixes: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        WatchedApp(id: "chrome", name: "Google Chrome", isBrowser: true, bundlePrefixes: ["com.google.Chrome"]),
        WatchedApp(id: "safari", name: "Safari", isBrowser: true, bundlePrefixes: ["com.apple.Safari", "com.apple.WebKit"]),
        WatchedApp(id: "firefox", name: "Firefox", isBrowser: true, bundlePrefixes: ["org.mozilla."]),
        WatchedApp(id: "brave", name: "Brave", isBrowser: true, bundlePrefixes: ["com.brave.Browser"]),
        WatchedApp(id: "arc", name: "Arc", isBrowser: true, bundlePrefixes: ["company.thebrowser."]),
        WatchedApp(id: "edge", name: "Microsoft Edge", isBrowser: true, bundlePrefixes: ["com.microsoft.edgemac"]),
    ]

    static func matching(bundleID: String) -> WatchedApp? {
        all.first { app in app.bundlePrefixes.contains { bundleID.hasPrefix($0) } }
    }
}

/// Polls Core Audio for which processes are capturing from any microphone (macOS 14.2+).
/// Needs no permissions. Reports when a watched app has held the mic for a few seconds
/// (call started) and when it has released it for a few seconds (call ended).
final class CallDetector {
    var onCallStarted: ((WatchedApp) -> Void)?
    var onCallEnded: ((WatchedApp) -> Void)?

    private var timer: Timer?
    private var firstSeen: [String: Date] = [:]     // app id → when it started using the mic
    private var lastSeen: [String: Date] = [:]      // app id → last poll it was using the mic
    private(set) var active: Set<String> = []       // app ids currently considered "in a call"

    private let startDelay: TimeInterval = 3        // ignore brief mic checks
    private let endDelay: TimeInterval = 6          // ride out short mute/device switches
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.monomi.voice-scribe"

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = Date()
        var usingMic = Set<String>()
        for bundleID in Self.bundleIDsCapturingInput() where !bundleID.hasPrefix(ownBundleID) {
            if let app = WatchedApp.matching(bundleID: bundleID) { usingMic.insert(app.id) }
        }

        for id in usingMic {
            if firstSeen[id] == nil { firstSeen[id] = now }
            lastSeen[id] = now
            if !active.contains(id), now.timeIntervalSince(firstSeen[id]!) >= startDelay,
               let app = WatchedApp.all.first(where: { $0.id == id }) {
                active.insert(id)
                onCallStarted?(app)
            }
        }

        for id in Set(firstSeen.keys).subtracting(usingMic) {
            guard let last = lastSeen[id], now.timeIntervalSince(last) >= endDelay else { continue }
            firstSeen[id] = nil
            lastSeen[id] = nil
            if active.remove(id) != nil, let app = WatchedApp.all.first(where: { $0.id == id }) {
                onCallEnded?(app)
            }
        }
    }

    // MARK: - Core Audio

    static func bundleIDsCapturingInput() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }

        return processes.compactMap { process in
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { return nil }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
                  let id = bundle?.takeRetainedValue() as String?, !id.isEmpty else { return nil }
            return id
        }
    }
}
