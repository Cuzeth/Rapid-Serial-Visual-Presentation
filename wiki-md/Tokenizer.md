# Tokenizer

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/tokenizer`

Splits raw text into discrete words for RSVP display.

## Overview

Handles whitespace splitting, soft-hyphen removal (U+00AD), non-breaking-hyphen normalization (U+2011 → ASCII hyphen), line-break hyphenation merging, and standalone punctuation attachment.

## API

### Type Methods
- `static func appendTokenizedText(String, into: inout [String], carry: inout String?)` - Tokenizes text and appends the resulting words to an existing array.
- `static func tokenize(String) -> [String]` - Tokenizes a complete text string into an array of words.
