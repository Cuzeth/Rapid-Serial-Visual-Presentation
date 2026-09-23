import Foundation

/// The words on either side of the current one, shown dimmed beside it when
/// context words are on.
nonisolated enum ContextWords {
    struct Neighbors: Equatable {
        let previous: String?
        let next: String?
    }

    /// The words on either side of `index`: nil past either end of the
    /// document, and on both sides for an index outside it.
    static func neighbors(of index: Int, in words: [String]) -> Neighbors {
        guard words.indices.contains(index) else {
            return Neighbors(previous: nil, next: nil)
        }
        return Neighbors(
            previous: index > 0 ? words[index - 1] : nil,
            next: index + 1 < words.count ? words[index + 1] : nil
        )
    }
}
