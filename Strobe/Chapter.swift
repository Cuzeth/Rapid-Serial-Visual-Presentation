import Foundation

struct Chapter: Codable, Identifiable, Hashable {
    var id: Int { wordIndex }
    let title: String
    let wordIndex: Int
}
