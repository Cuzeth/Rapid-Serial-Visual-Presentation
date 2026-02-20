# ZIPExtractor

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/zipextractor`

Extracts files from ZIP archives without external dependencies.

## Overview

Parses local file headers directly from the binary data and supports stored (method 0) and deflate (method 8) compression using Apple’s Compression framework. Used internally for EPUB extraction.

## API

### Type Methods
- `static func extract(zipAt: URL, to: URL) throws` - Extracts all files from a ZIP archive to a destination directory.
