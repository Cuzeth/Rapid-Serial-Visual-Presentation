import PDFKit

enum PDFTextExtractor {

    static func extractWords(from url: URL) -> [String] {
        guard let document = PDFDocument(url: url) else { return [] }

        var result: [String] = []
        result.reserveCapacity(document.pageCount * 250)

        var carry: String?
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string else { continue }

            let rawTokens = text
                .split(whereSeparator: \.isWhitespace)
                .map { normalizeToken(String($0)) }
                .filter { !$0.isEmpty }

            appendTokenized(rawTokens, into: &result, carry: &carry)
        }

        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        return result
    }

    static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var carry: String?

        let rawTokens = text
            .split(whereSeparator: \.isWhitespace)
            .map { normalizeToken(String($0)) }
            .filter { !$0.isEmpty }

        appendTokenized(rawTokens, into: &result, carry: &carry)
        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        return result
    }

    private static let compoundJoiners: Set<String> = [
        "a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to"
    ]

    private static func appendTokenized(
        _ rawTokens: [String],
        into output: inout [String],
        carry: inout String?
    ) {
        for token in rawTokens {
            if var pending = carry {
                if shouldMerge(pending: pending, with: token) {
                    pending = merge(pending: pending, with: token)
                    if pending.hasSuffix("-") {
                        carry = pending
                    } else {
                        output.append(pending)
                        carry = nil
                    }
                    continue
                }

                output.append(pending)
                carry = nil
            }

            if token.hasSuffix("-") {
                carry = token
            } else {
                output.append(token)
            }
        }
    }

    private static func shouldMerge(pending: String, with nextToken: String) -> Bool {
        guard pending.hasSuffix("-"),
              let nextFirst = nextToken.first,
              nextFirst.isLowercase else {
            return false
        }
        return true
    }

    private static func merge(pending: String, with nextToken: String) -> String {
        let stem = String(pending.dropLast())
        if shouldPreserveHyphen(stem: stem) {
            return stem + "-" + nextToken
        }
        return stem + nextToken
    }

    private static func shouldPreserveHyphen(stem: String) -> Bool {
        guard stem.contains("-") else { return false }

        let segments = stem.split(separator: "-")
        guard let last = segments.last else { return false }
        let lastSegment = last.lowercased()

        if compoundJoiners.contains(lastSegment) || lastSegment.count <= 2 {
            return true
        }

        if segments.count >= 3 && lastSegment.count <= 3 {
            return true
        }

        return false
    }

    private static func normalizeToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2011}", with: "-")
    }
}
