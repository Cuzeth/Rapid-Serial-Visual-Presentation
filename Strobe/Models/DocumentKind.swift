import Foundation

/// The kind of file a document came from, as its cover labels it.
nonisolated enum DocumentKind: Equatable {
    case epub
    case pdf
    case text
    case web

    /// Reads the kind from the stored file name. Pasted text stores its title
    /// as the file name, so anything without a known extension is text. A
    /// web page shared to Strobe stores its address.
    init(fileName: String) {
        let lowercased = fileName.lowercased()
        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            self = .web
            return
        }
        switch (fileName as NSString).pathExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        default: self = .text
        }
    }

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .text: "TEXT"
        case .web: "WEB"
        }
    }
}
