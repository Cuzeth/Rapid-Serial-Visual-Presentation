import Foundation

/// Encodes and decodes complexity score arrays as raw binary data
/// for compact external storage in SwiftData.
///
/// Each `Float` is stored as 4 bytes in native byte order. For a 100,000-word
/// document this produces ~400 KB — comparable to the word blob.
enum ComplexityStorage {

    /// Encodes a complexity score array into raw binary data.
    static func encode(_ scores: [Float]) -> Data {
        scores.withUnsafeBytes { Data($0) }
    }

    /// Decodes raw binary data back into a complexity score array.
    static func decode(_ data: Data) -> [Float] {
        guard !data.isEmpty else { return [] }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
    }
}
