# WordStorage

- **Type:** Enumeration
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/wordstorage`

Encodes and decodes word arrays as newline-delimited UTF-8 data for compact external storage in SwiftData.

## API

### Type Methods
- `static func decode(Data) -> [String]` - Decodes newline-delimited UTF-8 data back into a word array.
- `static func encode([String]) -> Data` - Encodes a word array into newline-delimited UTF-8 data.
