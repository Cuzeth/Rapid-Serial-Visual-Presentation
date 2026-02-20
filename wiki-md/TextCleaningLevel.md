# TextCleaningLevel

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/textcleaninglevel`

Controls the level of text cleaning applied during import.

## API

### Enumeration Cases
- `case none`
- `case standard`

### Initializers
- `init?(rawValue: String)`

### Instance Properties
- `var description: String`
- `var displayName: String`
- `var id: String`

### Type Properties
- `static let defaultValue: TextCleaningLevel`
- `static let storageKey: String`

### Type Methods
- `static func resolve(String) -> TextCleaningLevel`
