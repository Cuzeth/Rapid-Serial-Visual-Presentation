<p align="center">
  <img src="Assets/banner.svg" alt="Strobe — Rapid Serial Visual Presentation" width="100%" />
</p>

<h1 align="center">Read more. Move less.</h1>

<p align="center">
  <b>Strobe</b> is a free, open-source speed reader for iPhone, iPad, and Mac.
  It shows your books, papers, and articles one word at a time, each in the same spot,
  so your eyes can stay still and your attention stays on the words.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/strobe-speed-reader/id6759187873">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" width="160" />
  </a>
</p>

<p align="center">
  <a href="https://strobefast.app">
    <img src="https://img.shields.io/badge/Website-strobefast.app-FF3B30?style=for-the-badge" alt="Website" />
  </a>
  <a href="https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation/actions/workflows/tests.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/Cuzeth/Rapid-Serial-Visual-Presentation/tests.yml?style=for-the-badge&label=Tests" alt="Tests" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-Apache_2.0-green?style=for-the-badge" alt="License" />
  </a>
  <img src="https://img.shields.io/badge/Platform-iOS_17+_·_macOS_14+-lightgrey?style=for-the-badge&logo=apple" alt="Platform" />
</p>

<p align="center">
  <img src="AppStore/Screenshots/iPhone%206.9-inch/01-one-word.png" width="24%" alt="Reading Moby-Dick one word at a time, with the word's red focus letter in the center of the screen" />
  <img src="AppStore/Screenshots/iPhone%206.9-inch/03-hold-to-read.png" width="24%" alt="Holding to read, with a control for changing speed while the words play" />
  <img src="AppStore/Screenshots/iPhone%206.9-inch/05-while-reading.png" width="24%" alt="The previous and next words shown faintly beside the current word, with an open quote above it" />
  <img src="AppStore/Screenshots/iPhone%206.9-inch/08-full-text.png" width="24%" alt="The full text of Moby-Dick with the current word highlighted below a search field" />
</p>

## How it works

Reading a page keeps your eyes busy: hopping along every line, hunting for the start of the next one, finding your place again after every glance away. Strobe brings the words to you instead. Each one appears in the same spot, lined up on its red **Optimal Recognition Point**, so there's no line to follow and no place to lose. It's called **Rapid Serial Visual Presentation (RSVP)**, and it turns a wall of text into a steady stream.

Set any pace from **100 to 1,000 words per minute**. Start where you can follow comfortably and speed up as it clicks.

## Built for focused reading

### Hold to read. Let go to pause.

Press and hold anywhere on the screen to read, and lift your finger to stop. Slide up or down mid-sentence to change speed on the fly, and swipe sideways while paused to step word by word. Prefer hands-free? Turn off Hold to Read and tap to play instead.

### Pauses where a reader would.

Long words, acronyms, and hyphenated compounds get a little extra time. Sentence ends, commas, dashes, ellipses, and closing quotes each get their own pause, and you choose how long. Complexity timing lingers on rare words and names and breezes through the common ones, and an optional blank beat after each sentence gives you room to breathe.

### Never lose the thread.

Keep the previous and next words beside the one you're reading, and see an open quote or parenthesis hover above until it closes. Each new chapter shows its title as you reach it, so you always know where you are.

### The whole page, one tap away.

Open the full text with your place highlighted. Search for any word or phrase, jump between matches, and tap any word to pick up reading from there.

### Your words, your way.

Seven typefaces, from Fraunces to JetBrains Mono, at any size. Four text colors (Bright, Soft, Sepia, and Night) tone down the word and its red letter, and a true black background is made for reading in the dark. Every document remembers its own speed.

### Made for the keyboard.

On a Mac, or an iPad with a keyboard: <kbd>Space</kbd> reads and pauses, <kbd>←</kbd> <kbd>→</kbd> step through words, <kbd>Esc</kbd> goes back, <kbd>⌘N</kbd> starts a new text, and <kbd>⌘O</kbd> imports a file.

## Bring what you already read

<p align="center">
  <img src="AppStore/Screenshots/Mac/02-library.png" width="100%" alt="The Strobe library on the Mac: a Continue Reading banner above a grid of generated book covers" />
</p>

Import EPUB, PDF, plain-text, and Markdown files from Files or with drag and drop, or paste in an article and see its word count and reading time before you start. Every book gets its own cover, the one you're reading waits at the top, and Strobe picks up at your exact word.

- **Chapters at a glance.** EPUB tables of contents and PDF bookmarks become chapters, each with its reading time at your speed.
- **Clean text.** Page numbers, running headers, and footers are stripped on import.
- **Not just English.** Chinese, Japanese, and Korean text is split into words automatically, and Arabic keeps its connected letterforms.

DRM-protected EPUBs and password-protected PDFs can't be imported.

## Private by design

**Your reading is nobody else's business.** No account, no ads, no analytics, no cloud. Strobe reads your files on your device and never sends them anywhere, and its App Store privacy label says so: **Data Not Collected**.

## Free and open source

Strobe costs nothing: no subscription, no in-app purchases, no ads. Every line of it lives in this repo under the Apache 2.0 license. If it earns a place in your reading routine, you can [support development on Buy Me a Coffee](https://buymeacoffee.com/cuzeth) or give the repo a star.

---

## Under the hood

Strobe is SwiftUI and SwiftData with no third-party dependencies.

- **Import:** EPUBs are unzipped and read from their package manifest, with chapters from nested tables of contents and a DRM check up front. PDFs bring their bookmarks along.
- **Tokenizer:** rejoins words hyphenated across line breaks, splits words joined by em dashes, keeps `10:30 PM` and `44 B.C.` in one piece, and segments CJK text with `NLTokenizer`.
- **Timing:** word length, punctuation, acronyms, compounds, and per-word complexity scores (computed once at import with the NaturalLanguage framework) all shape how long each word stays up.
- **Tests:** 500+ Swift Testing cases, run on an iOS simulator and on macOS in CI.

## Build it yourself

1. Open `Strobe.xcodeproj` in Xcode 27.
2. Pick the **Strobe** scheme and an iPhone, iPad, or Mac to run on.
3. To run on your own device or Mac, choose your team under **Signing & Capabilities**.

There are no packages to resolve and no API keys to add.

## Contributing

Issues and pull requests are welcome. Keep changes focused, include tests when you can, and run the test suite before opening a PR.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
