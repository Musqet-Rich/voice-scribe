import Carbon
import Cocoa
import HotKey

/// Manages global hotkeys for push-to-talk and toggle recording
final class HotkeyManager {
    // Callbacks
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onToggle: (() -> Void)?

    // Current hotkey objects
    private var holdHotKey: HotKey?
    private var toggleHotKey: HotKey?

    // Track hold state for minimum duration check
    private var holdKeyDownTime: Date?
    private var isHolding = false

    /// Register default hotkeys (F1 = hold, F2 = toggle)
    func registerDefaults() {
        registerHoldHotkey(key: .f1, modifiers: [])
        registerToggleHotkey(key: .f2, modifiers: [])
    }

    /// Register the hold-to-talk hotkey
    func registerHoldHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        holdHotKey = nil // Remove existing

        let hotkey = HotKey(key: key, modifiers: modifiers)

        hotkey.keyDownHandler = { [weak self] in
            guard let self = self, !self.isHolding else { return }
            self.isHolding = true
            self.holdKeyDownTime = Date()
            self.onHoldStart?()
        }

        hotkey.keyUpHandler = { [weak self] in
            guard let self = self, self.isHolding else { return }
            self.isHolding = false
            self.onHoldEnd?()
            self.holdKeyDownTime = nil
        }

        self.holdHotKey = hotkey
    }

    /// Register the toggle recording hotkey
    func registerToggleHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        toggleHotKey = nil // Remove existing

        let hotkey = HotKey(key: key, modifiers: modifiers)

        hotkey.keyDownHandler = { [weak self] in
            self?.onToggle?()
        }

        self.toggleHotKey = hotkey
    }

    /// Unregister all hotkeys
    func unregisterAll() {
        holdHotKey = nil
        toggleHotKey = nil
    }
}
