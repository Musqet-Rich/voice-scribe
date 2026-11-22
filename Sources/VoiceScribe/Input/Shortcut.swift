import AppKit
import HotKey

/// A user-assigned trigger: either a normal key (optionally with modifiers), e.g. F19 or ⌃⌥⌘R,
/// or a modifier key pressed on its own, e.g. Fn or Right ⌥.
struct Shortcut: Codable, Hashable, Identifiable {
    let keyCode: UInt16
    /// NSEvent.ModifierFlags raw value (⌃⌥⇧⌘ only). Always empty for modifier-only shortcuts.
    let modifiers: UInt

    var id: String { "\(keyCode)-\(modifiers)" }

    var isModifierOnly: Bool { Self.modifierKeys[keyCode] != nil }
    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayName: String {
        if let mod = Self.modifierKeys[keyCode] { return mod.name }
        return KeyCombo(carbonKeyCode: UInt32(keyCode), carbonModifiers: modifierFlags.carbonFlags).description
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Modifier keys that can be used on their own, by virtual key code
    static let modifierKeys: [UInt16: (name: String, flag: NSEvent.ModifierFlags)] = [
        63: ("fn 🌐", .function),
        55: ("Left ⌘", .command), 54: ("Right ⌘", .command),
        58: ("Left ⌥", .option), 61: ("Right ⌥", .option),
        59: ("Left ⌃", .control), 62: ("Right ⌃", .control),
        56: ("Left ⇧", .shift), 60: ("Right ⇧", .shift),
    ]

    static let fn = Shortcut(keyCode: 63, modifiers: 0)
    static let f2 = Shortcut(keyCode: 120, modifiers: 0)
    static let ctrlOptCmdR = Shortcut(
        keyCode: 15, modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    )
}

/// The three things a shortcut can trigger
enum ShortcutAction: String, CaseIterable, Identifiable {
    case hold, toggle, call
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Hold to talk"
        case .toggle: return "Toggle dictation"
        case .call: return "Start/stop call recording"
        }
    }

    var defaults: [Shortcut] {
        switch self {
        case .hold: return [.fn]
        case .toggle: return [.f2]
        case .call: return [.ctrlOptCmdR]
        }
    }

    var storageKey: String { "shortcuts.\(rawValue)" }
}
