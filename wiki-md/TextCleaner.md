# TextCleaner

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/textcleaner`

## API

### Type Methods
- `static func cleanPages([String], level: TextCleaningLevel) -> [String]` - Cleans an array of page-level or section-level text strings. Cross-page analysis detects repeated headers/footers, then per-page rules strip boilerplate.
- `static func cleanText(String, level: TextCleaningLevel) -> String` - Cleans a single text block (no cross-page analysis).
