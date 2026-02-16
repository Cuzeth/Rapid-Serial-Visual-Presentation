import Foundation

/// A chapter marker within a document, identified by its starting word index.
struct Chapter: Codable, Identifiable, Hashable {
    /// Uses `wordIndex` as the stable identity since each chapter maps to a unique position.
    var id: Int { wordIndex }
    /// The display title of the chapter (e.g. "Chapter 1: Introduction").
    let title: String
    /// The index into the document's word array where this chapter begins.
    let wordIndex: Int
}
