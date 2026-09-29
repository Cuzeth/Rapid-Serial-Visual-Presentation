import Foundation

/// The app's `strobe://` links. The widget opens them, and the library
/// carries them out through ``AppRouter``.
///
/// The widget extension compiles this file too, so it stays free of
/// app-only types.
nonisolated enum AppLink: Equatable {
    /// The library, with nothing open over it: `strobe://library`.
    case library
    /// A document's reader at its saved position:
    /// `strobe://read?document=<uuid>`.
    case reader(documentID: UUID)

    static let scheme = "strobe"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .library:
            components.host = "library"
        case .reader(let documentID):
            components.host = "read"
            components.queryItems = [URLQueryItem(name: "document", value: documentID.uuidString)]
        }
        // A scheme, a host, and a UUID always make a valid URL.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Reads a `strobe://` link. Nil for other URLs and malformed links.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.host?.lowercased() {
        case "library":
            self = .library
        case "read":
            guard let value = components.queryItems?.first(where: { $0.name == "document" })?.value,
                  let documentID = UUID(uuidString: value) else {
                return nil
            }
            self = .reader(documentID: documentID)
        default:
            return nil
        }
    }
}
