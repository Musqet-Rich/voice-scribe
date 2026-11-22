import Carbon
import Cocoa
import HotKey

/// Global shortcuts, any number per action.
/// - Normal keys (F19, ⌃⌥⌘R…) use Carbon hotkeys, which swallow the key press.
/// - Modifier-only keys (Fn, Right ⌥…) are watched with NSEvent flagsChanged monitors.
///   They count as "used as a modifier" (and don't fire) if another key is pressed while held,
///   so Fn+Delete etc. keep working.
/// Needs Accessibility permission for the global monitors and simulated paste.
final class HotkeyManager {
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onHoldCancel: (() -> Void)?
    var onToggle: (() -> Void)?
    var onCallToggle: (() -> Void)?

    private var bindings: [ShortcutAction: [Shortcut]] = [:]
    private var hotKeys: [HotKey] = []
    private var monitors: [Any] = []

    /// Modifier-only keys currently held, mapped to whether another key was pressed meanwhile
    private var heldModifiers: [UInt16: Bool] = [:]
    /// Number of hold-to-talk keys currently down (normal + modifier-only)
    private var holdCount = 0
    private var suspended = false

    func register(_ bindings: [ShortcutAction: [Shortcut]]) {
        self.bindings = bindings
        guard !suspended else { return }
        install()
    }

    /// Temporarily disable all shortcuts (while the user is recording a new one)
    func suspend() {
        suspended = true
        uninstall()
    }

    func resume() {
        suspended = false
        install()
    }

    private func install() {
        uninstall()

        for (action, shortcuts) in bindings {
            for shortcut in shortcuts where !shortcut.isModifierOnly {
                let hk = HotKey(carbonKeyCode: UInt32(shortcut.keyCode),
                                carbonModifiers: shortcut.modifierFlags.carbonFlags)
                switch action {
                case .hold:
                    hk.keyDownHandler = { [weak self] in self?.holdPressed() }
                    hk.keyUpHandler = { [weak self] in self?.holdReleased(cancel: false) }
                case .toggle:
                    hk.keyDownHandler = { [weak self] in self?.onToggle?() }
                case .call:
                    hk.keyDownHandler = { [weak self] in self?.onCallToggle?() }
                }
                hotKeys.append(hk)
            }
        }

        let hasModifierOnly = bindings.values.contains { $0.contains(where: \.isModifierOnly) }
        guard hasModifierOnly else { return }

        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let keyDown: (NSEvent) -> Void = { [weak self] _ in self?.markModifiersUsed() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyDown) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keyDown($0); return $0 }) { monitors.append(m) }
    }

    private func uninstall() {
        hotKeys.removeAll()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        heldModifiers.removeAll()
        if holdCount > 0 {
            holdCount = 0
            onHoldCancel?()
        }
    }

    // MARK: - Hold logic (shared by all hold keys)

    private func holdPressed() {
        holdCount += 1
        if holdCount == 1 { onHoldStart?() }
    }

    private func holdReleased(cancel: Bool) {
        guard holdCount > 0 else { return }
        holdCount -= 1
        guard holdCount == 0 else { return }
        cancel ? onHoldCancel?() : onHoldEnd?()
    }

    // MARK: - Modifier-only keys

    private func actions(forModifierKey code: UInt16) -> [ShortcutAction] {
        bindings.compactMap { action, shortcuts in
            shortcuts.contains { $0.isModifierOnly && $0.keyCode == code } ? action : nil
        }
    }

    private func handleFlags(_ event: NSEvent) {
        guard let info = Shortcut.modifierKeys[event.keyCode] else { return }
        let actions = actions(forModifierKey: event.keyCode)
        guard !actions.isEmpty else { return }

        let isDown = event.modifierFlags.contains(info.flag)
        let wasDown = heldModifiers[event.keyCode] != nil

        if isDown && !wasDown {
            // Another modifier already held means this is a chord, not a lone press
            let otherMods = event.modifierFlags.intersection(Shortcut.relevantModifiers.union(.function))
                .subtracting(info.flag)
            heldModifiers[event.keyCode] = !otherMods.isEmpty
            if actions.contains(.hold) { holdPressed() }
        } else if !isDown && wasDown {
            let used = heldModifiers.removeValue(forKey: event.keyCode) ?? false
            if actions.contains(.hold) { holdReleased(cancel: used) }
            if !used {
                if actions.contains(.toggle) { onToggle?() }
                if actions.contains(.call) { onCallToggle?() }
            }
        }
    }

    private func markModifiersUsed() {
        for key in heldModifiers.keys { heldModifiers[key] = true }
    }

    /// Prompt for Accessibility permission (needed for the global monitors and ⌘V paste)
    static func ensureAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
