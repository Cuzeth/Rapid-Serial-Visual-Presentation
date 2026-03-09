import Foundation

/// Encodes and decodes word arrays as newline-delimited UTF-8 data
/// for compact external storage in SwiftData.
enum WordStorage {
    private static let separator = "\n"

    /// Encodes a word array into newline-delimited UTF-8 data.
    static func encode(_ words: [String]) -> Data {
        words.joined(separator: separator).data(using: .utf8) ?? Data()
    }

    /// Decodes newline-delimited UTF-8 data back into a word array.
    static func decode(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
    }
}
