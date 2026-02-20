# Document

- **Type:** Class
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/document`

A persisted document in the user’s library.

## Overview

Words are stored as a newline-delimited blob in external storage (`wordsBlob`) to keep the SQLite database lean. The legacy `words` array is retained only for migration from older versions.

## API

### Initializers
- `init(title: String, fileName: String, bookmarkData: Data, words: [String], chapters: [Chapter], currentWordIndex: Int, wordsPerMinute: Int)`

### Instance Properties
- `var bookmarkData: Data` - Security-scoped bookmark for re-accessing the original file.
- `var chapters: [Chapter]`
- `var currentWordIndex: Int`
- `var dateAdded: Date`
- `var fileName: String`
- `var id: UUID`
- `var lastReadDate: Date?`
- `var progress: Double` - Reading progress as a value from 0.0 to 1.0.
- `var progressPercentage: Int`
- `var readingWords: [String]` - The document’s words, resolved from `wordsBlob` (preferred) or the legacy `words` array. Results are cached in memory for the lifetime of the model object.
- `var title: String`
- `var wordCount: Int` - Stored separately so the list view can display word count without deserializing the entire words array.
- `var words: [String]` - Legacy word storage — empty for new documents. See `compactWordStorageIfNeeded()`.
- `var wordsBlob: Data?` - Newline-delimited word data stored externally to avoid bloating the database.
- `var wordsPerMinute: Int`

### Instance Methods
- `func compactWordStorageIfNeeded()` - Migrates words from the legacy `words` array to the `wordsBlob` external storage format. No-op if `wordsBlob` already exists or the legacy array is empty.
