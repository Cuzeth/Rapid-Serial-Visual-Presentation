# WordView

- **Type:** Structure
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/wordview`

Displays a single word with Optimal Recognition Point (ORP) highlighting.

## Overview

The ORP anchor letter (approximately at the 1/3 position of the word’s letters) is displayed in red and centered on screen. The rest of the word is offset so the reader’s eye stays fixed at the center. Font size scales down automatically for very long words.

## API

### Initializers
- `init(word: String, fontSize: CGFloat)`

### Instance Properties
- `var body: some View`
- `let fontSize: CGFloat`
- `let word: String`
