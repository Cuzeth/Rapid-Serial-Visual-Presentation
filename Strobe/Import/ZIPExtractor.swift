import Foundation
import Compression
import os

/// Extracts files from ZIP archives without external dependencies.
///
/// Parses the End-of-Central-Directory record at the tail of the archive
/// to find authoritative entry metadata, then reads each entry's compressed
/// payload via its local file header. Falls back to scanning local file
/// headers from the start for archives without a discoverable central
/// directory. Supports stored (method 0) and deflate (method 8) compression
/// using Apple's Compression framework. Used internally for EPUB extraction.
enum ZIPExtractor {

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
        category: "ZIPExtractor"
    )

    /// ZIP local file header signature (`PK\x03\x04`).
    nonisolated private static let localFileHeaderSignature: UInt32 = 0x04034b50

    /// Central directory file header signature (`PK\x01\x02`).
    nonisolated private static let centralDirectorySignature: UInt32 = 0x02014b50

    /// End of central directory record signature (`PK\x05\x06`).
    nonisolated private static let eocdSignature: UInt32 = 0x06054b50

    /// Fixed-size portion of the ZIP local file header (30 bytes).
    nonisolated private static let localFileHeaderSize = 30

    /// Fixed-size portion of the central directory file header (46 bytes).
    nonisolated private static let centralFileHeaderSize = 46

    /// Fixed-size portion of the end-of-central-directory record (22 bytes).
    nonisolated private static let eocdRecordSize = 22

    /// Maximum decompression buffer size (100 MB) to prevent ZIP bombs.
    nonisolated private static let maxDecompressionSize = 100 * 1024 * 1024

    /// Maximum cumulative bytes written for one archive (500 MB). The per-entry
    /// cap alone doesn't stop an archive packed with many large entries from
    /// exhausting temp storage.
    nonisolated private static let maxTotalExtractionSize = 500 * 1024 * 1024

    /// Extracts all files from a ZIP archive to a destination directory.
    /// - Parameters:
    ///   - source: The file URL of the ZIP archive.
    ///   - destination: The directory to extract files into (created if needed).
    ///   - maxTotalBytes: Cumulative extraction budget across all entries.
    ///     Entries that would exceed the remaining budget are skipped (not
    ///     written), bounding disk usage without failing the whole archive.
    /// - Throws: File system errors if directories cannot be created or files
    ///   written.
    nonisolated static func extract(
        zipAt source: URL,
        to destination: URL,
        maxTotalBytes: Int = maxTotalExtractionSize
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let data = try Data(contentsOf: source, options: .mappedIfSafe)

        try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let size = rawBuffer.count
            var budget = ExtractionBudget(remainingBytes: maxTotalBytes)

            if let eocdOffset = findEOCD(bytes: bytes, size: size) {
                try extractFromCentralDirectory(
                    bytes: bytes,
                    size: size,
                    eocdOffset: eocdOffset,
                    destination: destination,
                    fm: fm,
                    budget: &budget
                )
            } else {
                try extractByLocalHeaders(
                    bytes: bytes,
                    size: size,
                    destination: destination,
                    fm: fm,
                    budget: &budget
                )
            }
        }
    }

    /// Tracks the cumulative bytes a single archive is allowed to materialize.
    private struct ExtractionBudget {
        var remainingBytes: Int

        nonisolated mutating func charge(_ byteCount: Int) -> Bool {
            guard byteCount <= remainingBytes else { return false }
            remainingBytes -= byteCount
            return true
        }
    }

    // MARK: - Central directory path

    /// Locates the End of Central Directory record by scanning backwards from
    /// the file's tail. The EOCD comment field can be up to 65535 bytes, so
    /// the search window is bounded at `eocdRecordSize + 65535` bytes.
    nonisolated private static func findEOCD(bytes: UnsafePointer<UInt8>, size: Int) -> Int? {
        guard size >= eocdRecordSize else { return nil }
        let maxCommentLength = 65535
        let searchFloor = max(0, size - eocdRecordSize - maxCommentLength)
        var i = size - eocdRecordSize
        while i >= searchFloor {
            if readUInt32(bytes, at: i) == eocdSignature {
                let declaredCommentLength = Int(readUInt16(bytes, at: i + 20))
                if i + eocdRecordSize + declaredCommentLength == size {
                    return i
                }
            }
            i -= 1
        }
        return nil
    }

    /// Walks the central directory entries and extracts each one using the
    /// authoritative sizes recorded there (avoiding the data-descriptor
    /// ambiguity present in local file headers).
    nonisolated private static func extractFromCentralDirectory(
        bytes: UnsafePointer<UInt8>,
        size: Int,
        eocdOffset: Int,
        destination: URL,
        fm: FileManager,
        budget: inout ExtractionBudget
    ) throws {
        let totalEntries = Int(readUInt16(bytes, at: eocdOffset + 10))
        let cdSize = Int(readUInt32(bytes, at: eocdOffset + 12))
        let cdOffset = Int(readUInt32(bytes, at: eocdOffset + 16))

        guard cdOffset >= 0,
              cdSize >= 0,
              cdOffset + cdSize <= size else { return }

        let cdEnd = cdOffset + cdSize
        var entryOffset = cdOffset
        var entriesRead = 0

        while entryOffset + centralFileHeaderSize <= cdEnd, entriesRead < totalEntries {
            guard readUInt32(bytes, at: entryOffset) == centralDirectorySignature else { break }

            let compressionMethod = readUInt16(bytes, at: entryOffset + 10)
            let compressedSize = Int(readUInt32(bytes, at: entryOffset + 20))
            let uncompressedSize = Int(readUInt32(bytes, at: entryOffset + 24))
            let nameLength = Int(readUInt16(bytes, at: entryOffset + 28))
            let extraLength = Int(readUInt16(bytes, at: entryOffset + 30))
            let commentLength = Int(readUInt16(bytes, at: entryOffset + 32))
            let localHeaderOffset = Int(readUInt32(bytes, at: entryOffset + 42))

            let nameStart = entryOffset + centralFileHeaderSize
            guard nameStart + nameLength <= cdEnd else { break }
            let nameData = Data(bytes: bytes + nameStart, count: nameLength)

            entryOffset = nameStart + nameLength + extraLength + commentLength
            entriesRead += 1

            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else { continue }

            // Locate the actual compressed payload via the local file header.
            // The local header's name/extra lengths may differ from the central
            // directory's, so they must be re-read here rather than reused.
            guard localHeaderOffset >= 0,
                  localHeaderOffset + localFileHeaderSize <= size,
                  readUInt32(bytes, at: localHeaderOffset) == localFileHeaderSignature else {
                continue
            }
            let lhNameLength = Int(readUInt16(bytes, at: localHeaderOffset + 26))
            let lhExtraLength = Int(readUInt16(bytes, at: localHeaderOffset + 28))
            let dataStart = localHeaderOffset + localFileHeaderSize + lhNameLength + lhExtraLength
            guard dataStart + compressedSize <= size else { continue }

            try writeEntry(
                bytes: bytes,
                name: name,
                dataStart: dataStart,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                destination: destination,
                fm: fm,
                budget: &budget
            )
        }
    }

    // MARK: - Local header fallback

    /// Sequentially walks local file headers from the start of the archive.
    /// Used only when the End of Central Directory record cannot be found.
    /// Does not support entries that use data descriptors (GP-flag bit 3).
    nonisolated private static func extractByLocalHeaders(
        bytes: UnsafePointer<UInt8>,
        size: Int,
        destination: URL,
        fm: FileManager,
        budget: inout ExtractionBudget
    ) throws {
        var offset = 0
        while offset + localFileHeaderSize <= size {
            guard readUInt32(bytes, at: offset) == localFileHeaderSignature else { break }

            let compressionMethod = readUInt16(bytes, at: offset + 8)
            let compressedSize = Int(readUInt32(bytes, at: offset + 18))
            let uncompressedSize = Int(readUInt32(bytes, at: offset + 22))
            let nameLength = Int(readUInt16(bytes, at: offset + 26))
            let extraLength = Int(readUInt16(bytes, at: offset + 28))

            let nameStart = offset + localFileHeaderSize
            guard nameStart + nameLength <= size else { break }
            let nameData = Data(bytes: bytes + nameStart, count: nameLength)

            let dataStart = nameStart + nameLength + extraLength
            guard dataStart + compressedSize <= size else { break }

            if let name = String(data: nameData, encoding: .utf8), !name.isEmpty {
                try writeEntry(
                    bytes: bytes,
                    name: name,
                    dataStart: dataStart,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    compressionMethod: compressionMethod,
                    destination: destination,
                    fm: fm,
                    budget: &budget
                )
            }

            offset = dataStart + compressedSize
        }
    }

    // MARK: - Entry writing

    /// Materializes a single entry to disk, applying decompression, the
    /// Zip-Slip path-traversal guard, and the cumulative extraction budget.
    nonisolated private static func writeEntry(
        bytes: UnsafePointer<UInt8>,
        name: String,
        dataStart: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        compressionMethod: UInt16,
        destination: URL,
        fm: FileManager,
        budget: inout ExtractionBudget
    ) throws {
        let fileURL = destination.appendingPathComponent(name)

        // Prevent Zip Slip path traversal. Entry names come from the (possibly
        // malicious) archive, so they're logged with default privacy.
        guard fileURL.standardizedFileURL.path
            .hasPrefix(destination.standardizedFileURL.path + "/") else {
            logger.warning("Skipping ZIP entry with path traversal: \(name, privacy: .private)")
            return
        }

        if name.hasSuffix("/") {
            try fm.createDirectory(at: fileURL, withIntermediateDirectories: true)
            return
        }

        let parentDir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let fileData: Data
        if compressionMethod == 0 {
            fileData = Data(bytes: bytes + dataStart, count: compressedSize)
        } else if compressionMethod == 8 {
            let compressed = Data(bytes: bytes + dataStart, count: compressedSize)
            guard let decompressed = inflate(compressed, expectedSize: uncompressedSize) else {
                logger.warning("Deflate decompression failed for entry: \(name, privacy: .private)")
                return
            }
            fileData = decompressed
        } else {
            logger.warning("Unsupported compression method \(compressionMethod) for entry: \(name, privacy: .private)")
            return
        }

        // Skip (rather than abort on) entries that exceed the remaining budget:
        // the cap exists to bound disk usage, and legitimate media-heavy EPUBs
        // can exceed it with images/audio the text pipeline never reads. Small
        // text entries later in the archive still extract from what remains.
        guard budget.charge(fileData.count) else {
            logger.warning("Skipping entry over total extraction budget: \(name, privacy: .private) — possible ZIP bomb or oversized media")
            return
        }

        try fileData.write(to: fileURL)
    }

    // MARK: - Helpers

    /// Reads a little-endian UInt16 from the byte buffer.
    nonisolated private static func readUInt16(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    /// Reads a little-endian UInt32 from the byte buffer.
    nonisolated private static func readUInt32(_ bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
    }

    /// Decompresses raw deflate data using Apple's Compression framework.
    nonisolated private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        // Use Apple's Compression framework for raw deflate
        let capacity = max(expectedSize, data.count * 4)
        guard capacity <= maxDecompressionSize else {
            logger.warning("Decompression buffer exceeds \(maxDecompressionSize) bytes — possible ZIP bomb")
            return nil
        }
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
            // A nonzero declared size that doesn't match the actual output
            // means a corrupt or lying header — reject rather than silently
            // writing a truncated entry. (Zero means the size lives in a
            // trailing data descriptor, so there's nothing to verify against.)
            if expectedSize > 0 && decodedSize != expectedSize {
                logger.warning("Decompressed size \(decodedSize) != declared \(expectedSize) — rejecting entry")
                return nil
            }
            return Data(bytes: destinationBuffer, count: decodedSize)
        }

        return decompressed
    }
}
