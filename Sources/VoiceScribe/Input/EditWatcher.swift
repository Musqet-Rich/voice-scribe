import AppKit
import ApplicationServices
import Foundation

/// A word-level substitution the user made to pasted dictation
struct ObservedEdit: Equatable {
    let heard: String       // what Voice Scribe pasted
    let fixed: String       // what the user changed it to
    let context: String     // the full pasted text, for the AI judge
}

/// After a paste, watches the focused text field (via Accessibility) for up to a minute.
/// When watching ends (focus moves, time runs out, or a new dictation starts) it compares
/// the pasted region with what's there now and reports short word substitutions.
final class EditWatcher {
    var onEdits: (([ObservedEdit]) -> Void)?

    private var element: AXUIElement?
    private var pasted = ""
    private var prefixAnchor = ""
    private var suffixAnchor = ""
    private var latestText: String?
    private var timer: Timer?
    private var deadline = Date()

    private let watchDuration: TimeInterval = 60
    private let anchorLength = 24

    /// Start watching after `text` has been pasted into the focused field
    func watch(pasted text: String) {
        finish()  // evaluate any previous paste first
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Give the target app a moment to apply the paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.begin(trimmed)
        }
    }

    private func begin(_ text: String) {
        guard let element = Self.focusedElement(), let value = Self.value(of: element),
              let range = value.range(of: text, options: .backwards) else { return }

        self.element = element
        pasted = text
        prefixAnchor = String(value[value.startIndex..<range.lowerBound].suffix(anchorLength))
        suffixAnchor = String(value[range.upperBound...].prefix(anchorLength))
        latestText = value
        deadline = Date().addingTimeInterval(watchDuration)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let element else { return stopTimer() }
        // Stop when the user moves to another field or time is up
        if Date() > deadline { return finish() }
        if let focused = Self.focusedElement(), !CFEqual(focused, element) { return finish() }
        if let value = Self.value(of: element) { latestText = value } else { finish() }
    }

    /// Evaluate the edits made so far and stop watching
    func finish() {
        stopTimer()
        defer { element = nil; latestText = nil }
        guard element != nil, let text = latestText, let region = editedRegion(in: text) else { return }
        let edits = WordDiff.substitutions(from: pasted, to: region).map {
            ObservedEdit(heard: $0.0, fixed: $0.1, context: pasted)
        }
        if !edits.isEmpty { onEdits?(edits) }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Locate the (possibly edited) pasted text using the surrounding text as anchors
    private func editedRegion(in text: String) -> String? {
        var start = text.startIndex
        if !prefixAnchor.isEmpty {
            guard let r = text.range(of: prefixAnchor) else { return nil }
            start = r.upperBound
        }
        var end = text.endIndex
        if !suffixAnchor.isEmpty {
            guard let r = text.range(of: suffixAnchor, range: start..<text.endIndex) else { return nil }
            end = r.lowerBound
        }
        guard start <= end else { return nil }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Accessibility

    private static func focusedElement() -> AXUIElement? {
        // Electron apps (Slack, Teams, VS Code) only expose text once asked to
        if let app = NSWorkspace.shared.frontmostApplication {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func value(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}

/// Word-level diff that extracts short substitutions (1-3 words replaced by 1-3 words)
enum WordDiff {
    static func substitutions(from old: String, to new: String) -> [(String, String)] {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !a.isEmpty, !b.isEmpty, a.count < 2_000, b.count < 2_000 else { return [] }

        // LCS on words with punctuation stripped (case-sensitive, so "odoo" → "Odoo" counts as an edit)
        let na = a.map(clean), nb = b.map(clean)
        var dp = Array(repeating: Array(repeating: 0, count: nb.count + 1), count: na.count + 1)
        for i in stride(from: na.count - 1, through: 0, by: -1) {
            for j in stride(from: nb.count - 1, through: 0, by: -1) {
                dp[i][j] = na[i] == nb[j] && !na[i].isEmpty ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        // Walk the table, collecting runs of removed/added words between matches
        var results: [(String, String)] = []
        var i = 0, j = 0
        var removed: [String] = [], added: [String] = []
        func flush() {
            defer { removed.removeAll(); added.removeAll() }
            guard (1...3).contains(removed.count), (1...3).contains(added.count) else { return }
            let heard = clean(removed.joined(separator: " "))
            let fixed = clean(added.joined(separator: " "))
            // Ignore punctuation-only changes; keep case changes ("odoo" → "Odoo")
            guard !heard.isEmpty, !fixed.isEmpty, heard != fixed else { return }
            results.append((heard, fixed))
        }
        while i < na.count || j < nb.count {
            if i < na.count, j < nb.count, na[i] == nb[j], !na[i].isEmpty {
                flush(); i += 1; j += 1
            } else if j < nb.count, i == na.count || dp[i][j + 1] >= dp[i + 1][j] {
                added.append(b[j]); j += 1
            } else {
                removed.append(a[i]); i += 1
            }
        }
        flush()
        return results
    }

    /// Strip leading/trailing punctuation but keep internal characters (e.g. "Shift4", "my.musqet.tech")
    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}
