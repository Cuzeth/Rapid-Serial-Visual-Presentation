# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

**Do NOT run `xcodebuild` commands.** The user builds and tests separately in Xcode.

The project targets iOS 17.0+ and uses the `Strobe` scheme. CI runs on GitHub Actions with `macos-26` and `iPhone 17 Pro` simulator.

### Testing
Tests use the **Swift Testing** framework (not XCTest):
- `@Test` for test functions, `#expect` for assertions
- Test file: `StrobeTests/StrobeTests.swift`

## Architecture

Strobe is an RSVP (Rapid Serial Visual Presentation) speed reader for iOS. Users import PDFs/EPUBs or paste text, then read word-by-word with configurable timing.

### Data Flow
```
PDF/EPUB/Text → DocumentImportPipeline → Extractor → TextCleaner → Tokenizer → [String]
                                                                                    ↓
                                              Document (SwiftData) ← WordStorage (blob)
                                                                                    ↓
                                                        RSVPEngine → WordView (display)
```

### Key Layers

**Import Pipeline** (`Import/`): `DocumentImportPipeline` detects file type via UTType, routes to `EPUBTextExtractor` or `PDFTextExtractor`, then cleans and tokenizes. EPUB extraction uses `ZIPExtractor` → OPF parsing → HTML stripping. Returns `ImportResult` with words, chapters, source type, and title.

**Tokenizer** (`Engine/Tokenizer.swift`): Whitespace-based splitting with special handling for:
- Soft hyphen removal, non-breaking hyphen normalization
- Line-break hyphen merging (with compound-word detection)
- CJK text: detected by Unicode range, segmented via `NLTokenizer`, punctuation attached to preceding word
- Mixed-script text: character-by-character buffering switches between Latin and CJK

**RSVPEngine** (`Engine/RSVPEngine.swift`): `@Observable` class driving timer-based word advancement. Supports smart timing (duration scales with word length), sentence pauses (multiplier at sentence-ending punctuation across Latin, CJK, and Arabic scripts), and complexity timing (per-word duration modulation based on cognitive complexity scores).

**WordComplexityAnalyzer** (`Engine/WordComplexityAnalyzer.swift`): Scores each word's cognitive complexity (0.0–1.0) using NLTagger lexical class, named entity recognition, word frequency (built-in common word list), character composition, and word length. Scores are computed at import time and stored as a parallel `[Float]` blob via `ComplexityStorage`.

**WordView** (`Views/WordView.swift`): Renders words with Optimal Recognition Point (ORP) highlighting — anchor letter at ~1/3 position in red. Uses single `AttributedString` to preserve Arabic cursive shaping (color-only highlight, no bold) and correct glyph order. CJK short words use centered anchor.

**Persistence**: SwiftData `Document` model stores words externally as newline-delimited UTF-8 blob (`WordStorage`) and per-word complexity scores as raw Float binary (`ComplexityStorage`). In-memory caches (`cachedWords`, `cachedComplexity`) avoid repeated deserialization.

### Xcode Project
Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-mirrors the on-disk folder structure. Moving files on disk is sufficient; no `project.pbxproj` edits needed.

## Folder Structure
```
Strobe/
├── App/          App entry point, SwiftData container bootstrap
├── Engine/       RSVPEngine (playback), Tokenizer (word splitting), WordComplexityAnalyzer
├── Import/       DocumentImportPipeline, extractors, TextCleaner, ZIPExtractor
├── Models/       SwiftData models (Document, Chapter, WordStorage, ComplexityStorage)
├── Views/        All SwiftUI views
├── Theme/        StrobeTheme (colors, typography, hex parser)
├── Utilities/    HapticManager, ReaderFont
├── Fonts/        Custom font files (Fraunces, Inter, JetBrainsMono, PT*, SpaceGrotesk)
```

## Conventions

- **State management**: `@Observable` (not ObservableObject/Combine), `@Bindable`, `@AppStorage`
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- **Logging**: `os.Logger` with subsystem/category
- **Theme**: Dark mode only, background `0x050505`, accent "Strobe Red" `#FF3B30`
- **Error types**: `DocumentImportError` enum (`unsupportedFileType`, `epubExtractionFailed`, `noReadableText`)
- **Settings keys**: `defaultWPM`, `fontSize`, `smartTimingEnabled`, `sentencePauseEnabled`, `smartTimingPercentPerLetter`, `sentencePauseMultiplier`, `complexityTimingEnabled`, `complexityIntensity`, `readerFontSelection`, `textCleaningLevel`
