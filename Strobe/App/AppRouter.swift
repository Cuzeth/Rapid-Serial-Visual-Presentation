import Foundation
import Observation

/// Passes requests to open something to the library when they come from
/// outside it: widget taps and other `strobe://` links, and App Intents.
/// `ContentView` carries them out. On a cold launch, a request waits here
/// until the library appears.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// The request the library hasn't carried out yet.
    private(set) var pendingLink: AppLink?

    /// The document whose reader is on screen. A request for that document
    /// leaves its reader alone, because a reopened reader would load the
    /// position before the open one saves its own.
    @ObservationIgnored private(set) var openReaderDocumentID: UUID?

    func open(_ link: AppLink) {
        pendingLink = link
    }

    /// Returns the pending request and clears it.
    func takePendingLink() -> AppLink? {
        let link = pendingLink
        pendingLink = nil
        return link
    }

    func readerDidAppear(documentID: UUID) {
        openReaderDocumentID = documentID
    }

    func readerDidDisappear(documentID: UUID) {
        // Replacing one reader with another can show the new one before
        // the old one leaves.
        if openReaderDocumentID == documentID {
            openReaderDocumentID = nil
        }
    }
}
