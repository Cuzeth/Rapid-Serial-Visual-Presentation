# ReaderFont

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/readerfont`

The available font options for the RSVP reader display.

## Overview

Each case maps to a bundled font with regular and bold weights. Falls back to the system font if a custom font fails to load.

## API

### Enumeration Cases
- `case fraunces`
- `case inter`
- `case jetBrainsMono`
- `case ptMono`
- `case ptSans`
- `case ptSerif`
- `case spaceGrotesk`

### Initializers
- `init?(rawValue: String)`

### Instance Properties
- `var boldPostScriptName: String`
- `var displayName: String`
- `var id: String`
- `var regularPostScriptName: String`

### Instance Methods
- `func boldFont(size: CGFloat) -> Font` - Returns a SwiftUI `Font` for the bold weight at the given size.
- `func regularFont(size: CGFloat) -> Font` - Returns a SwiftUI `Font` for the regular weight at the given size.
- `func uiFont(size: CGFloat, bold: Bool) -> UIFont` - Returns a UIKit `UIFont`, with automatic fallback to the system font.

### Type Properties
- `static let defaultValue: ReaderFont`
- `static let storageKey: String` - The UserDefaults key used to persist the font selection.

### Type Methods
- `static func resolve(String) -> ReaderFont` - Resolves a stored raw value to a font case, falling back to the default.
