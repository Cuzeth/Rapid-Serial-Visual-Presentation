import Foundation
import Compression

enum ZIPExtractor {

    nonisolated static func extract(zipAt source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let data = try Data(contentsOf: source)

        try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let size = rawBuffer.count

            var offset = 0
            while offset + 30 <= size {
                // Local file header signature: 0x04034b50
                let sig = readUInt32(bytes, at: offset)
                guard sig == 0x04034b50 else { break }

                let compressionMethod = readUInt16(bytes, at: offset + 8)
                let compressedSize = Int(readUInt32(bytes, at: offset + 18))
                let uncompressedSize = Int(readUInt32(bytes, at: offset + 22))
                let nameLength = Int(readUInt16(bytes, at: offset + 26))
                let extraLength = Int(readUInt16(bytes, at: offset + 28))

                let nameStart = offset + 30
                guard nameStart + nameLength <= size else { break }
                let nameData = Data(bytes: bytes + nameStart, count: nameLength)
                guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                    offset = nameStart + nameLength + extraLength + compressedSize
                    continue
                }

                let dataStart = nameStart + nameLength + extraLength
                guard dataStart + compressedSize <= size else { break }

                let fileURL = destination.appendingPathComponent(name)

                if name.hasSuffix("/") {
                    // Directory entry
                    try fm.createDirectory(at: fileURL, withIntermediateDirectories: true)
                } else {
                    // File entry
                    let parentDir = fileURL.deletingLastPathComponent()
                    if !fm.fileExists(atPath: parentDir.path) {
                        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }

                    let fileData: Data
                    if compressionMethod == 0 {
                        // Stored (no compression)
                        fileData = Data(bytes: bytes + dataStart, count: compressedSize)
                    } else if compressionMethod == 8 {
                        // Deflate
                        let compressed = Data(bytes: bytes + dataStart, count: compressedSize)
                        guard let decompressed = inflate(compressed, expectedSize: uncompressedSize) else {
                            offset = dataStart + compressedSize
                            continue
                        }
                        fileData = decompressed
                    } else {
                        // Unsupported compression — skip
                        offset = dataStart + compressedSize
                        continue
                    }

                    try fileData.write(to: fileURL)
                }

                offset = dataStart + compressedSize
            }
        }
    }

    // MARK: - Helpers

    private static func readUInt16(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        // Use Apple's Compression framework for raw deflate
        let capacity = max(expectedSize, data.count * 4)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destinationBuffer.deallocate() }

        let decompressed = data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let source = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            let decodedSize = compression_decode_buffer(
                destinationBuffer, capacity,
                source, data.count,
                nil,
                COMPRESSION_ZLIB
            )
            guard decodedSize > 0 else { return nil }
            return Data(bytes: destinationBuffer, count: decodedSize)
        }

        return decompressed
    }
}
