# PDFTextExtractor

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/pdftextextractor`

Extracts tokenized words and chapter structure from PDF files using PDFKit.

## Overview

The extraction pipeline: read pages → clean text (cross-page header/footer detection + per-page boilerplate removal) → tokenize → extract chapters from the PDF outline.

## API

### Type Methods
- `static func extractWordsAndChapters(from: URL, cleaningLevel: TextCleaningLevel) -> PDFExtractionResult` - Extracts words and chapters from a PDF file.
