# ReaderView

- **Type:** Structure
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/readerview`

The RSVP reading interface — displays words one at a time.

## Overview

Gesture-driven: hold to play, release to pause, swipe to scrub. Includes a WPM slider, progress bar scrubber, and completion overlay. Persists reading state on disappear and scene phase changes.

## API

### Initializers
- `init(document: Document, startingWordIndex: Int?)`

### Instance Properties
- `var body: some View`
- `var document: Document`
