# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

**Do NOT run `xcodebuild` commands.** The user builds and tests separately in Xcode.

The project targets iOS 17.0+ / macOS 14.0+ and uses the `Strobe` scheme. CI runs on GitHub Actions on the `xcode-27` runner image with Xcode 27.0 selected, testing both an iOS simulator (any available iPhone, selected dynamically) and native macOS.

### Testing
Tests use the **Swift Testing** framework (not XCTest):
- `@Test` for test functions, `#expect` for assertions
- Test files: `StrobeTests/StrobeTests.swift` for the original suite, plus one file per feature (e.g. `SentenceBreakTests.swift`, `ContextWordsTests.swift`)

## Architecture

Strobe is an RSVP (Rapid Serial Visual Presentation) speed reader for iOS and macOS. Users import PDFs/EPUBs/plain-text files or paste text, then read word-by-word with configurable timing.

### Data Flow
```
PDF/EPUB/Text → DocumentImportPipeline → Extractor → TextCleaner → Tokenizer → [String]
                                                                                    ↓
                                              Document (SwiftData) ← WordStorage (blob)
                                                                                    ↓
                                                        RSVPEngine → WordView (display)
```

### Key Layers

**Import Pipeline** (`Import/`): `DocumentImportPipeline` detects file type via UTType, routes to `EPUBTextExtractor`, `PDFTextExtractor`, or a plain-text reader, then cleans and tokenizes. EPUB extraction uses `ZIPExtractor` → OPF parsing → DRM check (`META-INF/encryption.xml` vs. spine) → HTML stripping. Long phases check `Task.checkCancellation()` so the import overlay's Cancel works. Returns `ImportResult` with words, chapters, source type, and title.

**Tokenizer** (`Engine/Tokenizer.swift`): Whitespace-based splitting with special handling for:
- Soft hyphen removal, non-breaking hyphen normalization
- Line-break hyphen merging (with compound-word detection); a fragment followed by a bare joiner (`and`, `or`, `nor`, `to`, `and/or`, `und`, `oder`) is a suspended hyphen and stays unmerged (`pre- and post-war` → `pre-`, `and`, `post-war`)
- Dash splitting: words joined by an em dash, horizontal bar, or `--` become separate words with the dash kept on the first (`elements—stone` → `elements—`, `stone`); single hyphens and en-dash ranges stay whole
- Number units: a year and its era (`2000 BCE`, `44 B.C.`, `AD 79`) or a 12-hour time and its meridiem (`10:30 PM`, `5 p.m.`) become one word joined by a plain space, so a stored word can contain a space. The rules are strict: undotted lowercase designators (`ad`, `am`, `bc`) never join, and neither do mixed case, numbers with a prefix like `$` or `#`, or percentages. Units never join across an EPUB block: `appendTokenizedText(_:into:carry:startsBlock:)`
- CJK text: detected by Unicode range, segmented via `NLTokenizer`, punctuation attached to preceding word
- Mixed-script text: character-by-character buffering switches between Latin and CJK

**RSVPEngine** (`Engine/RSVPEngine.swift`): `@Observable` class driving timer-based word advancement. Supports smart timing (duration scales with word length; a configurable minimum word length keeps shorter words at the base rate), punctuation pauses (`Engine/PunctuationPause.swift`: a per-type multiplier for sentence ends, clause marks, dashes, ellipses, and closing brackets/quotes across Latin, CJK, and Arabic scripts — only a word's trailing marks count, and a word carrying several pauses once, for the longest), compound timing (`Engine/CompoundWord.swift`: always on; each further part of `wedge-shaped`, `and/or`, or a number unit like `2000 BCE` adds half a base interval, capped at four parts), acronym timing (`Engine/Acronym.swift`: always on; each letter name after the first in `FBI`, `PhD`, or `COVID-19` adds a quarter of a base interval, up to +0.75; three or more all-caps words in a row count as ordinary text, unless every one of them is followed by a comma, semicolon, or colon, as in a list), and complexity timing (per-word duration modulation based on cognitive complexity scores). `sentencePauseEnabled` gates all punctuation pauses; while it is on, smart timing drops its own trailing-punctuation bonus. Compound and acronym time are added to the word's time, and pauses and complexity then scale the whole word. Besides showing words, the engine has two phases:
- **Chapter announcement:** shows the chapter title in the word slot, then continues past the words at the chapter start that repeat the title. `Engine/ChapterHeading.swift` computes where reading resumes when chapters load; it compares letters and digits, so tokenizer splits and joins don't matter. `Chapter.wordIndex` still points at the heading.
- **Sentence break:** opt-in (`sentenceBreakEnabled`). After a sentence's last word the screen goes blank for `sentenceBreakLength` base intervals (`isInSentenceBreak`), on top of any sentence-end pause. `Engine/SentenceBreak.swift` makes the sentence-end test stricter than the pause's: no break after abbreviations or initials, and the next word must start a sentence. There is no break before a chapter start or after the last word.

Pausing or seeking ends either phase.

**WordComplexityAnalyzer** (`Engine/WordComplexityAnalyzer.swift`): Scores each word's cognitive complexity (0.0–1.0) using NLTagger lexical class, named entity recognition, word frequency (built-in common word list), character composition, and word length. Scores are computed at import time and stored as a parallel `[Float]` blob via `ComplexityStorage`.

**WordView** (`Views/WordView.swift`): Renders words with Optimal Recognition Point (ORP) highlighting — anchor character at ~1/3 of the word's letters and digits, in red. Uses single `AttributedString` to preserve Arabic cursive shaping (color-only highlight, no bold) and correct glyph order. CJK short words use centered anchor.

**Around the word** (both opt-in; they hide with the word during chapter announcements and sentence breaks, and their per-tick reads stay in small child views):
- **Context words:** the previous and next words sit inline on either side of the word, at its size, in the tone's faded color, with no anchor letter. They are overlays inside `WordView`, so the word never moves. A right-to-left document puts the previous word on the right.
- **`EnclosingMarksView`:** a `fixationSurround` subview of `ReaderStageLayout` showing the opening marks of any quotation or parenthetical the word is inside, above it. It sizes itself to the room between the bars, shrinking or hiding rather than moving the word. `Engine/EnclosingMarks.swift` computes the spans once per document, off the main thread.

**Persistence**: SwiftData `Document` model stores words externally as newline-delimited UTF-8 blob (`WordStorage`) and per-word complexity scores as raw Float binary (`ComplexityStorage`). In-memory caches (`cachedWords`, `cachedComplexity`) avoid repeated deserialization.

### Xcode Project
Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-mirrors the on-disk folder structure. Moving files on disk is sufficient; no `project.pbxproj` edits needed.

## Folder Structure
```
Strobe/
├── App/          App entry point, SwiftData container bootstrap
├── Engine/       RSVPEngine (playback), Tokenizer (word splitting), WordComplexityAnalyzer, per-word classifiers (PunctuationPause, CompoundWord, Acronym, SentenceBreak, ChapterHeading), EnclosingMarks
├── Import/       DocumentImportPipeline, extractors, TextCleaner, ZIPExtractor
├── Models/       SwiftData models (Document, Chapter, WordStorage, ComplexityStorage)
├── Views/        All SwiftUI views
├── Theme/        StrobeTheme (colors, typography, hex parser)
├── Utilities/    HapticManager, ReaderFont, ReaderTextTone
├── Fonts/        Custom font files (Fraunces, Inter, JetBrainsMono, PT*, SpaceGrotesk)
```

## Conventions

- **State management**: `@Observable` (not ObservableObject/Combine), `@Bindable`, `@AppStorage`
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- **Logging**: `os.Logger` with subsystem/category
- **Theme**: Dark mode only, background `0x050505`, accent "Strobe Red" `#FF3B30`
- **Reader colors**: the RSVP word, ORP anchor, chapter announcement, and passage text take their colors from `ReaderTextTone` (`bright`, `soft`, `sepia`, `night`), never from `StrobeTheme` or system colors. App chrome stays on `StrobeTheme`.
- **Reader background**: reading surfaces (reader, passage view, the reader's chapter picker, settings tone swatches) paint `ReaderBackdrop()`, which follows `trueBlackBackgroundEnabled`; never a `StrobeTheme` background.
- **Reader layout**: `ReaderStageLayout` pins the bars and centers the word on a fixation line at a fixed fraction of the full screen height, so the word never moves when chrome fades or options toggle. Additions around the word go in overlays or their own stage role (`fixationSurround` for content centered on the word), never in a stack with the word. iPhone runs in portrait only; iPad windows and macOS windows can be any size.
- **Typography**: Fraunces (`titleFont`) for headings and for large display numerals in Settings cards (WPM, text size — `titleFont(size: 32)` in `textPrimary`); body text and captions use `bodyFont`. Keep sibling numerals styled identically.
- **Error types**: `DocumentImportError` enum (`unsupportedFileType`, `epubExtractionFailed`, `epubDRMProtected`, `pdfLoadFailed`, `pdfPasswordProtected`, `noReadableText`)
- **Settings keys**: `defaultWPM`, `fontSize`, `smartTimingEnabled`, `sentencePauseEnabled`, `smartTimingPercentPerLetter`, `smartTimingMinimumWordLength`, `sentencePauseMultiplier`, `complexityTimingEnabled`, `complexityIntensity`, `clausePauseMultiplier`, `dashPauseMultiplier`, `ellipsisPauseMultiplier`, `bracketPauseMultiplier`, `holdToReadEnabled`, `holdSpeedAdjustEnabled`, `trueBlackBackgroundEnabled`, `readingHeaderTitleEnabled`, `readingHeaderChapterEnabled`, `sentenceBreakEnabled`, `sentenceBreakLength`, `contextWordsEnabled`, `enclosingMarksEnabled` — all registered in `ReaderSettings.Keys`/`Defaults` (plus app flags `hasSeenTutorial`, `didCompactLegacyWordStorage`; timing settings also go in `TimingSnapshot`). `readerFontSelection`, `readerTextTone`, and `textCleaningLevel` are the `storageKey` of `ReaderFont`, `ReaderTextTone`, and `TextCleaningLevel`. Never use raw key strings
- **Navigation**: value-based (`NavigationLink(value:)` + `navigationDestination` in `ContentView`, `ReaderRoute` for chapter entries) — eager `destination:` links would decode word blobs for every visible row. `ReaderView` loads word blobs asynchronously in `.task`, never in `init`.
- **Platform conditionals**: `#if os(iOS)` / `#if os(macOS)` for UIKit/AppKit imports, haptics, presentation modifiers, and hint text. Engine, import pipeline, and models are fully cross-platform.
- **macOS keyboard shortcuts**: Space (play/pause), Left/Right arrows (scrub), Escape (dismiss reader) — via `.onKeyPress`, also works on iPad with hardware keyboard
- **macOS haptics**: `HapticManager` is no-op on macOS (all methods are empty stubs)
