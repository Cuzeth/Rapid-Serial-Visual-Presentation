import PDFKit

enum PDFTextExtractor {

    nonisolated static func extractWords(from url: URL) -> [String] {
        guard let document = PDFDocument(url: url) else { return [] }

        var result: [String] = []
        result.reserveCapacity(document.pageCount * 250)

        var carry: String?
        for i in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: i),
                      let text = page.string else { return }
                appendTokenizedText(text, into: &result, carry: &carry)
            }
        }

        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        return result
    }

    nonisolated static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var carry: String?

        appendTokenizedText(text, into: &result, carry: &carry)
        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        return result
    }

    nonisolated private static let compoundJoiners: Set<String> = [
        "a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to"
    ]

    nonisolated private static func appendTokenizedText(
        _ text: String,
        into output: inout [String],
        carry: inout String?
    ) {
        var tokenBuffer = String()
        tokenBuffer.reserveCapacity(32)

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                appendBufferedToken(tokenBuffer, into: &output, carry: &carry)
                tokenBuffer.removeAll(keepingCapacity: true)
                continue
            }

            if scalar.value == 0x00AD {
                continue
            }

            if scalar.value == 0x2011 {
                tokenBuffer.append("-")
            } else {
                tokenBuffer.unicodeScalars.append(scalar)
            }
        }

        appendBufferedToken(tokenBuffer, into: &output, carry: &carry)
    }

    nonisolated private static func appendBufferedToken(
        _ token: String,
        into output: inout [String],
        carry: inout String?
    ) {
        guard !token.isEmpty else { return }

        if var pending = carry {
            if shouldMerge(pending: pending, with: token) {
                pending = merge(pending: pending, with: token)
                if pending.hasSuffix("-") {
                    carry = pending
                } else {
                    output.append(pending)
                    carry = nil
                }
                return
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

    nonisolated private static func shouldMerge(pending: String, with nextToken: String) -> Bool {
        guard pending.hasSuffix("-"),
              let nextFirst = nextToken.first,
              nextFirst.isLowercase else {
            return false
        }
        return true
    }

    nonisolated private static func merge(pending: String, with nextToken: String) -> String {
        let stem = String(pending.dropLast())
        if shouldPreserveHyphen(stem: stem) {
            return stem + "-" + nextToken
        }
        return stem + nextToken
    }

    nonisolated private static func shouldPreserveHyphen(stem: String) -> Bool {
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
}
