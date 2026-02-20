# Strobe Wiki

Documentation exported from `Strobe.doccarchive` for easy copy/paste into GitHub Wiki.

## Classes
- [Document](Document) - A persisted document in the user’s library.
- [HapticManager](HapticManager) - Provides haptic feedback for reading interactions.
- [RSVPEngine](RSVPEngine) - Drives the word-by-word Rapid Serial Visual Presentation playback.

## Structures
- [Chapter](Chapter) - A chapter marker within a document, identified by its starting word index.
- [ChapterListView](ChapterListView) - Displays the chapter list for a document with progress indicators.
- [ContentView](ContentView) - The main library view displaying imported documents in a grid.
- [DocumentCard](DocumentCard) - A grid card displaying a document’s title, progress percentage, and word count.
- [EPUBExtractionResult](EPUBExtractionResult) - The result of extracting text from an EPUB file.
- [ImportResult](ImportResult) - The result of a document import operation.
- [PDFExtractionResult](PDFExtractionResult) - The result of extracting text from a PDF file.
- [ReaderView](ReaderView) - The RSVP reading interface — displays words one at a time.
- [SettingsView](SettingsView) - App settings sheet for configuring reading speed, font, text size, and behavior.
- [StrobeApp](StrobeApp) - The app entry point. Bootstraps the SwiftData model container and displays a diagnostic error view if persistence initialization fails.
- [StrobeCardButtonStyle](StrobeCardButtonStyle) - A button style with a subtle scale-down press animation for card-style buttons.
- [StrobeTheme](StrobeTheme) - Centralized design tokens for the Strobe app — colors, gradients, and typography.
- [TutorialView](TutorialView) - Full-screen onboarding tutorial shown on first launch. A paged walkthrough introducing import, reading controls, chapters, and settings.
- [WordView](WordView) - Displays a single word with Optimal Recognition Point (ORP) highlighting.

## Enumerations
- [DocumentImportError](DocumentImportError) - Errors that can occur during document import.
- [DocumentImportPipeline](DocumentImportPipeline) - Routes document files to the appropriate extractor based on file type.
- [DocumentSourceType](DocumentSourceType) - The detected file format of an imported document.
- [EPUBTextExtractor](EPUBTextExtractor) - Extracts tokenized words and chapter structure from EPUB files.
- [PDFTextExtractor](PDFTextExtractor) - Extracts tokenized words and chapter structure from PDF files using PDFKit.
- [ReaderFont](ReaderFont) - The available font options for the RSVP reader display.
- [TextCleaner](TextCleaner)
- [TextCleaningLevel](TextCleaningLevel) - Controls the level of text cleaning applied during import.
- [Tokenizer](Tokenizer) - Splits raw text into discrete words for RSVP display.
- [WordStorage](WordStorage) - Encodes and decodes word arrays as newline-delimited UTF-8 data for compact external storage in SwiftData.
- [ZIPExtractor](ZIPExtractor) - Extracts files from ZIP archives without external dependencies.

## Extended Modules
- [SwiftUICore](SwiftUICore)

