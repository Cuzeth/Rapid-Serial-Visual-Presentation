# DocumentImportPipeline

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/documentimportpipeline`

Routes document files to the appropriate extractor based on file type.

## Overview

Serves as the entry point for the import pipeline: detects the source type, delegates to `PDFTextExtractor` or `EPUBTextExtractor`, and resolves the display title from metadata or the filename.

## API

### Type Properties
- `static let supportedContentTypes: [UTType]` - The content types the app can import via the file picker.

### Type Methods
- `static func extractWordsAndChapters(from: URL, detectedContentType: UTType?, cleaningLevel: TextCleaningLevel) throws -> ImportResult` - Extracts words and chapters from a document file.
- `static func resolveSourceType(for: URL, detectedContentType: UTType?) -> DocumentSourceType` - Determines the document format from the system-detected content type or, as a fallback, from the file extension.
- `static func resolveTitle(metadataTitle: String?, fileName: String) -> String` - Returns the document’s metadata title if available, otherwise cleans up the filename.
