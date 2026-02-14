import Foundation

enum WordStorage {
    private static let separator = "\n"

    static func encode(_ words: [String]) -> Data {
        words.joined(separator: separator).data(using: .utf8) ?? Data()
    }

    static func decode(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
    }
}
