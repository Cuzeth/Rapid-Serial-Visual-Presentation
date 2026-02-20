# HapticManager

- **Type:** Class
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/hapticmanager`

Provides haptic feedback for reading interactions.

## Overview

Uses pre-prepared feedback generators for minimal latency. Each method fires its feedback and immediately re-prepares for the next use.

## API

### Instance Methods
- `func completedReading()` - Reached the end of the text during playback
- `func playPause()` - Finger down (play) or finger up (pause)
- `func scrubBoundary()` - Hit the beginning or end while scrubbing
- `func scrubTick()` - Each word change during scrubbing
- `func wpmChanged()` - WPM slider snapped to a new value

### Type Properties
- `static let shared: HapticManager`
