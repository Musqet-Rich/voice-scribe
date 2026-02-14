import Foundation

/// Manages text corrections loaded from a JSON dictionary file.
/// Format: `{"original_text": "corrected_text", ...}` (simple dict, compatible with voice server)
final class CorrectionsManager {
    private(set) var corrections: [Correction] = []

    private let fileURL: URL

    init() {
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voice-scribe")
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.fileURL = baseDir.appendingPathComponent("corrections.json")
        load()
    }

    /// Load corrections from disk
    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            corrections = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let dict = try JSONDecoder().decode([String: String].self, from: data)
            corrections = dict.map { Correction(original: $0.key, corrected: $0.value) }
                .sorted { $0.original.lowercased() < $1.original.lowercased() }
        } catch {
            print("Failed to load corrections: \(error)")
            corrections = []
        }
    }

    /// Save corrections to disk
    func save() {
        var dict: [String: String] = [:]
        for c in corrections {
            dict[c.original] = c.corrected
        }
        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save corrections: \(error)")
        }
    }

    /// Apply all corrections to a text string (case-insensitive word boundary matching)
    func apply(_ text: String) -> String {
        var result = text
        for correction in corrections {
            // Use word boundary regex for accurate replacement
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: correction.original))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: correction.corrected
            )
        }
        return result
    }

    /// Add a new correction
    func add(original: String, corrected: String) {
        // Remove existing if same original
        corrections.removeAll { $0.original.lowercased() == original.lowercased() }
        corrections.append(Correction(original: original, corrected: corrected))
        corrections.sort { $0.original.lowercased() < $1.original.lowercased() }
        save()
    }

    /// Remove a correction by original text
    func remove(original: String) {
        corrections.removeAll { $0.original == original }
        save()
    }

    /// Export corrections as JSON data
    func exportData() -> Data? {
        var dict: [String: String] = [:]
        for c in corrections { dict[c.original] = c.corrected }
        return try? JSONEncoder().encode(dict)
    }

    /// Import corrections from JSON data (merges with existing)
    func importData(_ data: Data) throws {
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        for (original, corrected) in dict {
            add(original: original, corrected: corrected)
        }
    }
}
