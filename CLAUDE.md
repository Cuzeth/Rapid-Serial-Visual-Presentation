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

**Import Pipeline** (`Import/`): `DocumentImportPipeline` detects file type via UTType, routes to `EPUBTextExtractor`, `PDFTextExtractor`, or a plain-text reader, then cleans and tokenizes. EPUB extraction uses `ZIPExtractor` → OPF parsing → DRM check (`META-INF/encryption.xml` vs. spine) → HTML stripping. Long phases check `Task.checkCancellation()` so the importing tile's Cancel works. Returns `ImportResult` with words, chapters, source type, and title.

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
- **Context words:** the previous and next words sit inline on either side of the word, at its size, with no anchor letter: in the tone's faded color while paused, and at its `dimTextOpacity` (near 1.3:1, barely visible) while playing. They are overlays inside `WordView`, so the word never moves. A right-to-left document puts the previous word on the right.
- **`EnclosingMarksView`:** a `fixationSurround` subview of `ReaderStageLayout` showing the opening marks of any quotation or parenthetical the word is inside, above it. It sizes itself to the room between the bars, shrinking or hiding rather than moving the word. `Engine/EnclosingMarks.swift` computes the spans once per document, off the main thread.

**Library and app chrome** (`Views/`): `ContentView` is the navigation root and the library: a grid of generated covers (`DocumentCover`: the title in Fraunces on a `CoverTone` picked by hashing the document's UUID, so it survives relaunches) under `ContinueReadingCard`, the most recently read unfinished document (hidden while searching and in a one-document library). `ChapterListView` is the book page for documents with chapters: cover, Start Reading / Resume / Read Again, progress, and chapter rows with their length at the document's speed. Settings is a grouped `Form` sheet on iOS (Timing and While Reading are pushed pages) and a tabbed `Settings` scene on macOS, both built from the sections in `Views/Settings/`. First launch shows `WelcomeView` (`hasSeenTutorial`), whose header plays a sentence through `WordView`. Reading status, time left, and file kind come from `Models/ReadingStatus.swift`, `ReadingTime.swift`, and `DocumentKind.swift`. `Document+Library.swift` applies them to a document.

**Outside the app** (`Intents/`, `StrobeWidget/`): both open documents through `strobe://` links (`App/AppLink.swift`: `strobe://read?document=<uuid>`, `strobe://library`) or requests to `AppRouter`, which `ContentView` carries out. A request for the document whose reader is already open leaves that reader alone. "Up next" (`Models/Document+UpNext.swift`) is the most recently read unfinished document, or else the newest unstarted one.
- **Continue Reading widget** (`StrobeWidget/`, small and medium everywhere, Lock Screen families on iOS): the extension can't open the SwiftData store. It reads a `ContinueReadingSnapshot` of the up-next document from the App Group's defaults (`SharedContainer`, `group.com.abdeen.strobe`). `App/LibraryObserver.swift` rewrites the snapshot after every `ModelContext.didSave` and reloads the widget only when the snapshot changed. It also refreshes the document titles that App Shortcut phrases use.
- **App Intents**: Continue Reading, Open Document (an `OpenIntent` on `DocumentEntity`), Get Reading Progress (speaks the progress and returns the percentage), and Speed Read Text (adds text through `TextImport` and opens it). `StrobeShortcuts` gives Siri phrases to all of them except Speed Read Text. Intents run in the app process and use `StrobeApp.sharedBootstrap`'s container and its `mainContext` (`IntentLibrary`), so their saves reach the library, the widget, and sync.

**Persistence**: SwiftData `Document` model stores words externally as newline-delimited UTF-8 blob (`WordStorage`) and per-word complexity scores as raw Float binary (`ComplexityStorage`). In-memory caches (`cachedWords`, `cachedComplexity`) avoid repeated deserialization.

**iCloud sync** (`Sync/`): `CKSyncEngine` beside SwiftData, not SwiftData's CloudKit mode. The store and its schema don't change for sync, and each device's library stays local-first. `LibrarySync` (started in `StrobeApp.init`, toggled by `iCloudSyncEnabled`) reconciles after every `ModelContext.didSave`: `CloudSyncLedger` diffs the library against what iCloud last confirmed and queues what changed. The ledger is a binary plist in Application Support/CloudSync, never in the store. Remote changes are merged on the main context and saved, so `didSave` observers see them. Each document has two records in the private database's `Library` zone: `book-<UUID>` (title, file name, date added, chapters, words and complexity as assets, content hash) and `state-<UUID>` (position, furthest, speed, last read, `modifiedAt`), so reading never re-sends a book. Field values are encrypted. Merge rules (`StampedReadingPosition.merged`): the later-set resume point and speed win, and only a change to those restamps a position. The furthest point and last-read date only move forward. A rename made here beats an older title from iCloud. Safety rules, which keep sync from ever deleting a book the user didn't delete:
  - Nothing uploads until a full fetch has shown what iCloud has. A local copy never uploaded, of a book iCloud already has (same title, word count, and words; typically imported on two devices before they synced), folds its reading into that book and leaves instead of uploading.
  - Nothing else is merged away: two copies both already in iCloud stay as two books.
  - A deletion is only sent for a document the ledger saw in the library that has since left it. It's never sent because ledger state is missing or unreadable, belongs to another store (`NSStoreUUID`), or lost track of many documents at once; each of those re-matches instead.
  - A book deleted elsewhere while open here waits until `marksDocumentOpen` views close. Its reading goes to an identical local copy if there is one.
  - A record iCloud no longer has is uploaded again rather than deleted here.
  - Signing out keeps the library, which is matched against and uploaded to the next account.
  - Strobe's data deleted from iCloud turns sync off and keeps the library.
  - Bookmarks don't sync.

### Xcode Project
Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-mirrors the on-disk folder structure. Moving files on disk is sufficient; no `project.pbxproj` edits needed.

Targets: `Strobe` (the app, which embeds the widget), `StrobeTests`, and `StrobeWidgetExtension` (the `StrobeWidget/` folder). The widget also compiles a few files from `Strobe/`, listed in the "Exceptions for "Strobe" folder in "StrobeWidgetExtension" target" set: `AppLink`, `ContinueReadingSnapshot`, `DocumentKind`, `ReadingStatus`, `ReadingTime`, `StrobeTheme`, `SharedContainer`, `DocumentCover`, and the Fraunces font. Keep those files free of app-only types such as `Document`. Add a file to that list when the widget needs it. The app and the widget each have an entitlements file for the App Group. The widget's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must match the app's.

## Folder Structure
```
Strobe/
├── App/          App entry point, SwiftData container bootstrap, File menu commands, strobe:// links (AppLink, AppRouter), LibraryObserver
├── Engine/       RSVPEngine (playback), Tokenizer (word splitting), WordComplexityAnalyzer, per-word classifiers (PunctuationPause, CompoundWord, Acronym, SentenceBreak, ChapterHeading), EnclosingMarks
├── Import/       DocumentImportPipeline, extractors, TextCleaner, ZIPExtractor, TextImport
├── Intents/      App Intents: DocumentEntity and its query, the reading intents, StrobeShortcuts
├── Models/       SwiftData models (Document, Chapter, WordStorage, ComplexityStorage), library display helpers, ContinueReadingSnapshot
├── Views/        All SwiftUI views; Settings/ holds the settings sections
├── Theme/        StrobeTheme (colors, typography, hex parser)
├── Sync/         iCloud sync: LibrarySync (CKSyncEngine delegate), CloudSyncLedger (pure diff/merge state), CloudRecords (record schema)
├── Utilities/    HapticManager, ReaderFont, ReaderTextTone
├── Fonts/        Custom font files (Fraunces, Inter, JetBrainsMono, PT*, SpaceGrotesk)
StrobeWidget/     Continue Reading widget extension: the widget, its views, Info.plist, entitlements, assets
```

## Conventions

- **State management**: `@Observable` (not ObservableObject/Combine), `@Bindable`, `@AppStorage`
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- **Logging**: `os.Logger` with subsystem/category
- **Theme**: Dark mode only, background `0x050505`, accent "Strobe Red" `#FF3B30` (also the asset catalog's AccentColor and the root `.tint`). Red marks reading: progress, the ORP anchor, and at most one primary action per screen. Toolbar and menu controls stay neutral (`.tint(.primary)`).
- **App chrome**: system navigation bars and toolbars, `.searchable`, `Form`, `ContentUnavailableView`, and sheet toolbars with `.cancellationAction`/`.confirmationAction`. No custom headers, round icon buttons, or floating action buttons outside the reader (`CircleIconButton` belongs to the reader's top bar).
- **Reader colors**: the RSVP word, ORP anchor, chapter announcement, and passage text take their colors from `ReaderTextTone` (`bright`, `soft`, `sepia`, `night`), never from `StrobeTheme` or system colors. App chrome stays on `StrobeTheme`.
- **Reader background**: reading surfaces (reader, passage view, the reader's chapter picker, the settings preview and tone swatches, the welcome demo) paint `ReaderBackdrop()`, which follows `trueBlackBackgroundEnabled`; never a `StrobeTheme` background.
- **Reader layout**: `ReaderStageLayout` pins the bars and centers the word on a fixation line at a fixed fraction of the full screen height, so the word never moves when chrome fades or options toggle. Additions around the word go in overlays or their own stage role (`fixationSurround` for content centered on the word), never in a stack with the word. iPhone runs in portrait only; iPad windows and macOS windows can be any size.
- **Typography**: interface text outside the reader uses system text styles (SF Pro with Dynamic Type), with `StrobeTheme.metadataFont` for small secondary text such as status and word counts. Fraunces SemiBold (`StrobeTheme.displayFont`) is for book titles, generated covers, and the welcome headline. The reader's own chrome keeps `titleFont` and `bodyFont` (Space Grotesk); don't restyle it.
- **Error types**: `DocumentImportError` enum (`unsupportedFileType`, `epubExtractionFailed`, `epubDRMProtected`, `pdfLoadFailed`, `pdfPasswordProtected`, `noReadableText`)
- **Settings keys**: `defaultWPM`, `fontSize`, `smartTimingEnabled`, `sentencePauseEnabled`, `smartTimingPercentPerLetter`, `smartTimingMinimumWordLength`, `sentencePauseMultiplier`, `complexityTimingEnabled`, `complexityIntensity`, `clausePauseMultiplier`, `dashPauseMultiplier`, `ellipsisPauseMultiplier`, `bracketPauseMultiplier`, `holdToReadEnabled`, `holdSpeedAdjustEnabled`, `trueBlackBackgroundEnabled`, `readingHeaderTitleEnabled`, `readingHeaderChapterEnabled`, `sentenceBreakEnabled`, `sentenceBreakLength`, `contextWordsEnabled`, `enclosingMarksEnabled`, `iCloudSyncEnabled` — all registered in `ReaderSettings.Keys`/`Defaults` (plus app flags `hasSeenTutorial`, `didCompactLegacyWordStorage`, `iCloudSyncStoppedAfterDeletion`; timing settings also go in `TimingSnapshot`). `readerFontSelection`, `readerTextTone`, and `textCleaningLevel` are the `storageKey` of `ReaderFont`, `ReaderTextTone`, and `TextCleaningLevel`. Never use raw key strings
- **Navigation**: value-based (`NavigationLink(value:)` + `navigationDestination` in `ContentView`, `ReaderRoute` for chapter rows, the book page's main button, and Continue Reading) — eager `destination:` links would decode word blobs for every visible row. `ReaderView` loads word blobs asynchronously in `.task`, never in `init`.
- **Platform conditionals**: `#if os(iOS)` / `#if os(macOS)` for UIKit/AppKit imports, haptics, presentation modifiers, and hint text. Engine, import pipeline, and models are fully cross-platform.
- **macOS window**: the default title bar with a unified toolbar (title, sort and add menus, search). `LibraryCommands` puts New Text… and Import File… in the File menu through `FocusedValues.libraryActions`. The reader hides the window's back button and title but keeps an empty, transparent toolbar so the traffic lights stay.
- **macOS keyboard shortcuts**: Space (play/pause), Left/Right arrows (scrub), Escape (dismiss reader or book page) — via `.onKeyPress`, also works on iPad with hardware keyboard. ⌘N (New Text…) and ⌘O (Import File…) are menu commands.
- **macOS haptics**: `HapticManager` is no-op on macOS (all methods are empty stubs)
- **Syncing documents**: save every `Document` change with `ModelContext.save()` (any context of the app's container); sync picks up saves, not unsaved edits. Deleting a `Document` deletes it from iCloud on every device, so never delete or replace documents (or the store) as housekeeping. A view that shows one document adds `.marksDocumentOpen(document.id)`. To sync a new `Document` property, add a field to the `Book` or `ReadingState` record in `CloudRecords.swift` and its ledger comparison. CloudKit fields can be added once deployed to production, never renamed or removed.
- **Entitlements**: `Strobe/Strobe.entitlements` (both platforms) holds the iCloud container `iCloud.com.abdeen.strobe`. Because of it, every `ModelConfiguration` must pass `cloudKitDatabase: .none`: the default `.automatic` turns on SwiftData's own CloudKit mirroring, and the store then fails to load (unique `id`, non-defaulted attributes). Push Notifications and Background Modes > Remote notifications are added in Xcode's Signing & Capabilities, which writes each platform's key. Sync works without them and fetches when the app comes forward. The macOS sandbox allows outgoing connections for CloudKit.
