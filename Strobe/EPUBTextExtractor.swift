import Foundation

struct EPUBExtractionResult {
    let words: [String]
    let chapters: [Chapter]
}

enum EPUBTextExtractor {

    nonisolated static func extractWordsAndChapters(from url: URL) throws -> EPUBExtractionResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ZIPExtractor.extract(zipAt: url, to: tempDir)

        let opfRelativePath = try findOPFPath(in: tempDir)
        let opfURL = tempDir.appendingPathComponent(opfRelativePath)
        let opfDir = opfURL.deletingLastPathComponent()

        let opf = try parseOPF(at: opfURL)

        // Extract words from spine-ordered XHTML files
        var words: [String] = []
        words.reserveCapacity(opf.spineItems.count * 500)
        var spineWordOffsets: [String: Int] = [:]
        var carry: String?

        for itemID in opf.spineItems {
            guard let href = opf.manifest[itemID] else { continue }
            let fileURL = opfDir.appendingPathComponent(href)
            spineWordOffsets[href] = words.count

            autoreleasepool {
                guard let data = try? Data(contentsOf: fileURL),
                      let text = stripHTML(data) else { return }
                Tokenizer.appendTokenizedText(text, into: &words, carry: &carry)
            }
        }

        if let carry, !carry.isEmpty {
            words.append(carry)
        }

        // Extract chapters from NCX or NAV
        let chapters = extractChapters(
            opf: opf,
            opfDir: opfDir,
            spineWordOffsets: spineWordOffsets,
            totalWordCount: words.count
        )

        return EPUBExtractionResult(words: words, chapters: chapters)
    }

    // MARK: - container.xml → OPF path

    nonisolated private static func findOPFPath(in epubDir: URL) throws -> String {
        let containerURL = epubDir
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        let data = try Data(contentsOf: containerURL)
        let parser = SimpleXMLParser()
        parser.parse(data: data)

        // Look for <rootfile full-path="..."/>
        for element in parser.elements where element.name == "rootfile" {
            if let fullPath = element.attributes["full-path"], !fullPath.isEmpty {
                return fullPath
            }
        }
        throw DocumentImportError.epubExtractionFailed
    }

    // MARK: - OPF parsing

    private struct OPFResult {
        let manifest: [String: String]   // id → href
        let spineItems: [String]          // ordered item IDs
        let tocID: String?                // NCX manifest ID
        let navHref: String?              // EPUB3 nav document href
    }

    nonisolated private static func parseOPF(at url: URL) throws -> OPFResult {
        let data = try Data(contentsOf: url)
        let parser = SimpleXMLParser()
        parser.parse(data: data)

        var manifest: [String: String] = [:]
        var spineItems: [String] = []
        var tocID: String?
        var navHref: String?

        for element in parser.elements {
            switch element.name {
            case "item":
                if let id = element.attributes["id"],
                   let href = element.attributes["href"] {
                    let decodedHref = href.removingPercentEncoding ?? href
                    manifest[id] = decodedHref
                    // EPUB3 nav detection
                    if let properties = element.attributes["properties"],
                       properties.contains("nav") {
                        navHref = decodedHref
                    }
                }
            case "itemref":
                if let idref = element.attributes["idref"] {
                    spineItems.append(idref)
                }
            case "spine":
                tocID = element.attributes["toc"]
            default:
                break
            }
        }

        return OPFResult(
            manifest: manifest,
            spineItems: spineItems,
            tocID: tocID,
            navHref: navHref
        )
    }

    // MARK: - Chapter extraction

    nonisolated private static func extractChapters(
        opf: OPFResult,
        opfDir: URL,
        spineWordOffsets: [String: Int],
        totalWordCount: Int
    ) -> [Chapter] {
        // Try EPUB3 nav first, then NCX
        if let navHref = opf.navHref {
            let navURL = opfDir.appendingPathComponent(navHref)
            let navDir = navURL.deletingLastPathComponent()
            if let chapters = parseNavDocument(
                at: navURL, navDir: navDir, opfDir: opfDir,
                spineWordOffsets: spineWordOffsets
            ), !chapters.isEmpty {
                return chapters
            }
        }

        if let tocID = opf.tocID,
           let tocHref = opf.manifest[tocID] {
            let ncxURL = opfDir.appendingPathComponent(tocHref)
            let ncxDir = ncxURL.deletingLastPathComponent()
            if let chapters = parseNCX(
                at: ncxURL, ncxDir: ncxDir, opfDir: opfDir,
                spineWordOffsets: spineWordOffsets
            ), !chapters.isEmpty {
                return chapters
            }
        }

        return []
    }

    // MARK: - EPUB3 Nav parsing

    nonisolated private static func parseNavDocument(
        at url: URL,
        navDir: URL,
        opfDir: URL,
        spineWordOffsets: [String: Int]
    ) -> [Chapter]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = SimpleXMLParser()
        parser.parse(data: data)

        var chapters: [Chapter] = []

        // Nav documents use <a href="...">Title</a> inside <li> elements
        for element in parser.elements where element.name == "a" {
            guard let href = element.attributes["href"],
                  let title = element.text, !title.isEmpty else { continue }

            let fileHref = href.components(separatedBy: "#").first ?? href
            guard !fileHref.isEmpty else { continue }

            if let wordIndex = resolveWordIndex(
                href: fileHref, referenceDir: navDir, opfDir: opfDir,
                spineWordOffsets: spineWordOffsets
            ) {
                chapters.append(Chapter(title: title.trimmingCharacters(in: .whitespacesAndNewlines), wordIndex: wordIndex))
            }
        }

        return deduplicateChapters(chapters)
    }

    // MARK: - NCX parsing

    nonisolated private static func parseNCX(
        at url: URL,
        ncxDir: URL,
        opfDir: URL,
        spineWordOffsets: [String: Int]
    ) -> [Chapter]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = NCXParser()
        parser.parse(data: data)

        var chapters: [Chapter] = []

        // Top-level navPoints only
        for navPoint in parser.navPoints {
            guard let title = navPoint.title, !title.isEmpty,
                  let src = navPoint.src else { continue }

            let fileHref = src.components(separatedBy: "#").first ?? src
            guard !fileHref.isEmpty else { continue }

            if let wordIndex = resolveWordIndex(
                href: fileHref, referenceDir: ncxDir, opfDir: opfDir,
                spineWordOffsets: spineWordOffsets
            ) {
                chapters.append(Chapter(title: title, wordIndex: wordIndex))
            }
        }

        return deduplicateChapters(chapters)
    }

    // MARK: - Href resolution

    nonisolated private static func resolveWordIndex(
        href: String,
        referenceDir: URL,
        opfDir: URL,
        spineWordOffsets: [String: Int]
    ) -> Int? {
        let decodedHref = href.removingPercentEncoding ?? href
        let resolvedURL = referenceDir.appendingPathComponent(decodedHref).standardized

        // Make relative to opfDir for spine lookup
        let opfDirPath = opfDir.standardized.path + "/"
        let resolvedPath = resolvedURL.path
        guard resolvedPath.hasPrefix(opfDirPath) else { return nil }
        let relativeToOPF = String(resolvedPath.dropFirst(opfDirPath.count))

        return spineWordOffsets[relativeToOPF]
    }

    nonisolated private static func deduplicateChapters(_ chapters: [Chapter]) -> [Chapter] {
        guard !chapters.isEmpty else { return [] }
        var result = chapters.sorted { $0.wordIndex < $1.wordIndex }
        var seen = Set<Int>()
        result = result.filter { seen.insert($0.wordIndex).inserted }
        return result
    }

    // MARK: - HTML stripping

    nonisolated private static func stripHTML(_ data: Data) -> String? {
        let html = String(decoding: data, as: UTF8.self)
        guard !html.isEmpty else { return nil }

        var output = String()
        output.reserveCapacity(html.count / 3)

        var inTag = false
        var inScript = false
        var inStyle = false
        var tagBuffer = String()

        for char in html {
            if char == "<" {
                inTag = true
                tagBuffer.removeAll(keepingCapacity: true)
                continue
            }

            if inTag {
                if char == ">" {
                    inTag = false
                    let tag = tagBuffer.lowercased().trimmingCharacters(in: .whitespaces)
                    let tagName = tag.split(separator: " ").first.map(String.init) ?? tag

                    if tagName == "script" { inScript = true }
                    else if tagName == "/script" { inScript = false }
                    else if tagName == "style" { inStyle = true }
                    else if tagName == "/style" { inStyle = false }

                    // Block-level elements get a space to prevent word joining
                    let blockTags: Set<String> = [
                        "p", "/p", "div", "/div", "br", "br/",
                        "h1", "/h1", "h2", "/h2", "h3", "/h3",
                        "h4", "/h4", "h5", "/h5", "h6", "/h6",
                        "li", "/li", "blockquote", "/blockquote",
                        "tr", "/tr", "td", "/td", "th", "/th",
                        "section", "/section", "article", "/article"
                    ]
                    if blockTags.contains(tagName) {
                        output.append(" ")
                    }

                    tagBuffer.removeAll(keepingCapacity: true)
                } else {
                    tagBuffer.append(char)
                }
                continue
            }

            if inScript || inStyle { continue }

            if char == "&" {
                // Peek-free entity handling: just insert a space
                // Full entity resolution isn't needed for tokenization
                output.append(" ")
                continue
            }

            output.append(char)
        }

        // Decode common HTML entities that the simple & handler missed
        return output
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Simple XML Parser (flat element collection)

private final class SimpleXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    struct Element {
        let name: String
        let attributes: [String: String]
        var text: String?
    }

    private(set) var elements: [Element] = []
    private var currentText: String?
    private var currentElementIndex: Int?

    nonisolated func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        elements.append(Element(name: localName, attributes: attributes))
        currentElementIndex = elements.count - 1
        currentText = ""
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText?.append(string)
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if let index = currentElementIndex, let text = currentText, !text.isEmpty {
            elements[index].text = text
        }
        currentElementIndex = nil
        currentText = nil
    }
}

// MARK: - NCX Parser (navPoint extraction)

private final class NCXParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    struct NavPoint {
        var title: String?
        var src: String?
        let depth: Int
    }

    private(set) var navPoints: [NavPoint] = []
    private var depth = 0
    private var inNavPoint = false
    private var inText = false
    private var currentTitle: String?
    private var currentSrc: String?
    private var navPointDepth = 0

    nonisolated func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "navPoint":
            depth += 1
            if depth == 1 {
                // Top-level navPoint only
                inNavPoint = true
                navPointDepth = depth
                currentTitle = nil
                currentSrc = nil
            }
        case "text":
            if inNavPoint && depth == navPointDepth + 1 {
                inText = true
            }
        case "content":
            if inNavPoint && depth == navPointDepth + 1 {
                currentSrc = attributes["src"]?.removingPercentEncoding ?? attributes["src"]
            }
        default:
            break
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            if currentTitle == nil {
                currentTitle = string
            } else {
                currentTitle?.append(string)
            }
        }
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "navPoint":
            if inNavPoint && depth == navPointDepth {
                navPoints.append(NavPoint(
                    title: currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                    src: currentSrc,
                    depth: navPointDepth
                ))
                inNavPoint = false
            }
            depth -= 1
        case "text":
            inText = false
        default:
            break
        }
    }
}
