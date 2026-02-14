import AppKit
import CoreGraphics
import Foundation

/// Handles pasting text at the cursor position via clipboard + simulated ⌘V
final class PasteManager {
    /// Paste text at the current cursor position
    /// Saves and restores the previous clipboard content
    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard content
        let previousContents = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()

            // Restore previous clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    /// Simulate ⌘V keystroke using CGEvent
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code 9 = 'V'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("Failed to create CGEvent for paste")
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
