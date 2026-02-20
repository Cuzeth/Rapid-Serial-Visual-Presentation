# Strobe

[![Tests](https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation/actions/workflows/tests.yml/badge.svg)](https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation/actions/workflows/tests.yml)

Strobe is an iOS rapid-serial-visual-presentation (RSVP) reader for PDF and EPUB files. It presents one word at a time so you can read long material with less eye movement and tighter focus.

## Features

- Import PDF and EPUB files from the system file picker.
- Read with an RSVP interface (one word at a time).
- Hold to play, release to pause, and swipe to scrub.
- Adjust reading speed (`100-1000` WPM), text size, and font.
- Optional Smart Timing and Sentence Pauses.
- Chapter list navigation with progress tracking.
- Local persistence with SwiftData and security-scoped file bookmarks.
- Built-in onboarding tutorial and haptic feedback.

## Tech Stack

- Swift 5
- SwiftUI
- SwiftData
- PDFKit
- UniformTypeIdentifiers
- XCTest + Swift Testing

## Requirements

- macOS with Xcode 15 or newer
- iOS deployment target: 17.0

## Getting Started

1. Open `Strobe.xcodeproj` in Xcode.
2. Select the `Strobe` scheme.
3. Choose an iOS Simulator or a connected iPhone.
4. Press Run.

## Build and Test (CLI)

Build:

```bash
xcodebuild \
  -project Strobe.xcodeproj \
  -scheme Strobe \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build
```

Run tests:

```bash
xcodebuild test \
  -project Strobe.xcodeproj \
  -scheme Strobe \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

If that simulator is unavailable on your machine, replace `name=iPhone 16` with an installed simulator device.

## Usage

1. Launch the app and tap `+` to import a PDF or EPUB.
2. Open a document card from the library.
3. If chapters exist, choose a chapter or read from the start.
4. Hold on the reader screen to play; release to pause.
5. Use Settings to tune speed, font, text size, and behavior.

## Project Structure

- `Strobe/` - app source code
- `StrobeTests/` - unit/integration tests (Swift Testing)
- `StrobeUITests/` - UI tests (XCTest)
- `Strobe.doccarchive/` - generated DocC archive
- `wiki-md/` - generated Markdown docs for GitHub Wiki

## Documentation

GitHub Wiki:

- https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation/wiki

Wiki-ready Markdown files in this repo:

- `wiki-md/`

Regenerate them from the DocC archive with:

```bash
./wiki-md/.generate-from-docc.sh
```

## Contributing

Issues and pull requests are welcome. Keep changes focused, include tests when possible, and run the test suite before submitting.

## License

No license file is currently included in this repository.
