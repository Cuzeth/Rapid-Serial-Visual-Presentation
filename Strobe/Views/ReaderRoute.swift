import Foundation

/// Value-based navigation target for opening the reader at a specific word.
///
/// Library cards navigate on the `Document` itself; chapter rows navigate on
/// a `ReaderRoute` so they can carry a starting position. Both destinations
/// are registered on the `NavigationStack` in `ContentView`. Value-based
/// links keep `ReaderView` from being constructed until the user actually
/// navigates (eager `destination:` links build every visible row's reader).
struct ReaderRoute: Hashable {
    let document: Document
    let startingWordIndex: Int?

    init(document: Document, startingWordIndex: Int? = nil) {
        self.document = document
        self.startingWordIndex = startingWordIndex
    }
}
