# EPUBTextExtractor

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/epubtextextractor`

Extracts tokenized words and chapter structure from EPUB files.

## Overview

Supports both EPUB 2 (NCX table of contents) and EPUB 3 (nav document). The extraction pipeline: unzip → parse OPF manifest → read spine-ordered XHTML files → strip HTML → clean text → tokenize.

## API

### Type Methods
- `static func extractWordsAndChapters(from: URL, cleaningLevel: TextCleaningLevel) throws -> EPUBExtractionResult` - Extracts words and chapters from an EPUB file.
