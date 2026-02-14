import Foundation

/// A single transcription result with timestamp
struct TranscriptionItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let correctedText: String
    let timestamp: Date
    let duration: TimeInterval

    init(text: String, correctedText: String, duration: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.correctedText = correctedText
        self.timestamp = Date()
        self.duration = duration
    }
}
