import Foundation

/// A text correction rule (original → corrected)
struct Correction: Identifiable, Codable, Hashable {
    var id: String { original }
    let original: String
    let corrected: String
}
