import AppKit
import SwiftUI

/// Settings section for assigning any number of keys to each action
struct ShortcutsSection: View {
    @ObservedObject var appState: AppState
    @State private var recordingFor: ShortcutAction?
    @State private var recorder = KeyRecorder()

    var body: some View {
        Section("Shortcuts") {
            ForEach(ShortcutAction.allCases) { action in
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                    FlowRow {
                        ForEach(appState.shortcuts[action] ?? []) { shortcut in
                            chip(shortcut, action: action)
                        }
                        if recordingFor == action {
                            Text("Press a key… (Esc to cancel)")
                                .font(.callout)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(5)
                        } else {
                            Button("+ Add key") { startRecording(for: action) }
                                .buttonStyle(.borderless)
                                .disabled(recordingFor != nil)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("Single modifier keys (fn, Right ⌥…) work too: press and release one on its own.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Reset") { appState.resetShortcuts() }
                    .buttonStyle(.borderless)
            }
            Text("Using fn? Set System Settings → Keyboard → \"Press 🌐 key to\" → Do Nothing. Voice Scribe needs Accessibility permission (Privacy & Security → Accessibility).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onDisappear { stopRecording() }
    }

    private func chip(_ shortcut: Shortcut, action: ShortcutAction) -> some View {
        HStack(spacing: 4) {
            Text(shortcut.displayName)
                .font(.system(.callout, design: .rounded).weight(.medium))
            Button {
                appState.removeShortcut(shortcut, from: action)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.18))
        .cornerRadius(5)
    }

    private func startRecording(for action: ShortcutAction) {
        recordingFor = action
        appState.hotkeyManager.suspend()
        recorder.start { shortcut in
            if let shortcut { appState.addShortcut(shortcut, to: action) }
            stopRecording()
        }
    }

    private func stopRecording() {
        guard recordingFor != nil else { return }
        recorder.stop()
        recordingFor = nil
        appState.hotkeyManager.resume()
    }
}

/// Captures the next key press in the app (normal key with modifiers, or a lone modifier key)
final class KeyRecorder {
    private var monitor: Any?
    private var pendingModifier: UInt16?
    private var completion: ((Shortcut?) -> Void)?

    func start(_ completion: @escaping (Shortcut?) -> Void) {
        stop()
        self.completion = completion
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil  // swallow while recording
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pendingModifier = nil
        completion = nil
    }

    private func finish(_ shortcut: Shortcut?) {
        let done = completion
        stop()
        done?(shortcut)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            pendingModifier = nil
            let mods = event.modifierFlags.intersection(Shortcut.relevantModifiers)
            if event.keyCode == 53, mods.isEmpty {  // Esc cancels
                finish(nil)
                return
            }
            finish(Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue))

        case .flagsChanged:
            guard let info = Shortcut.modifierKeys[event.keyCode] else { return }
            if event.modifierFlags.contains(info.flag) {
                pendingModifier = event.keyCode
            } else if pendingModifier == event.keyCode {
                // Pressed and released on its own
                finish(Shortcut(keyCode: event.keyCode, modifiers: 0))
            }

        default:
            break
        }
    }
}

/// Simple wrapping horizontal layout for chips
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
