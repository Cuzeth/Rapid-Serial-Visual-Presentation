# RSVPEngine

- **Type:** Class
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/rsvpengine`

Drives the word-by-word Rapid Serial Visual Presentation playback.

## Overview

Manages a timer that advances through the word array at the configured words-per-minute rate. Supports smart timing (longer display for long words) and sentence pauses (extra delay at sentence-ending punctuation).

Conforms to `@Observable` so SwiftUI views automatically update when `currentIndex`, `isPlaying`, or settings change.

## API

### Initializers
- `init(words: [String], currentIndex: Int, wordsPerMinute: Int, smartTimingEnabled: Bool, sentencePauseEnabled: Bool)`

### Instance Properties
- `var currentIndex: Int` - The index of the word currently being displayed.
- `var currentWord: String` - The word at the current playback position, or an empty string if out of bounds.
- `var isAtEnd: Bool` - Whether the playback position is at the last word.
- `var isPlaying: Bool` - Whether playback is currently running.
- `var progress: Double` - Playback progress as a value from 0.0 to 1.0.
- `var sentencePauseEnabled: Bool` - When enabled, words ending with `.`, `!`, or `?` receive extra display time.
- `var smartTimingEnabled: Bool` - When enabled, longer words are displayed for proportionally more time.
- `var words: [String]` - The full array of words to display.
- `var wordsPerMinute: Int` - The target reading speed. Changing this during playback restarts the timer.

### Instance Methods
- `func pause()` - Stops playback and invalidates the timer.
- `func play()` - Starts playback from the current position. No-op if already playing or at end.
- `func restart()` - Resets playback to the beginning of the word array.
- `func scrub(by: Int) -> Bool` - Moves the position by `delta` words. Returns `true` if the move was clamped (hit a boundary).
- `func seek(to: Int)` - Jumps to a specific word index, clamped to valid bounds.

### Type Properties
- `static let sentencePauseMultiplier: Double` - Extra multiplier applied when sentence pause is enabled.

### Type Methods
- `static func endsWithSentencePunctuation(String) -> Bool` - Returns `true` if the word ends with sentence-terminating punctuation (`.`, `!`, `?`).
- `static func smartTimingMultiplier(for: String) -> Double` - Returns a timing multiplier (1.0–1.7) based on word length and trailing punctuation.
