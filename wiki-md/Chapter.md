# Chapter

- **Type:** Structure
- **Module:** Strobe
- **DocC Path:** `/documentation/strobe/chapter`

A chapter marker within a document, identified by its starting word index.

## API

### Initializers
- `init(from: any Decoder) throws`
- `init(title: String, wordIndex: Int)`

### Instance Properties
- `var id: Int` - Uses `wordIndex` as the stable identity since each chapter maps to a unique position.
- `let title: String` - The display title of the chapter (e.g. “Chapter 1: Introduction”).
- `let wordIndex: Int` - The index into the document’s word array where this chapter begins.
