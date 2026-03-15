import Foundation
import NaturalLanguage

/// Assigns a cognitive complexity score (0.0–1.0) to each word in an array.
///
/// Scores reflect how much processing time a reader needs for each word.
/// Function words like "the" and "is" score low; rare vocabulary, proper nouns,
/// and words with digits or mixed case score high. The scores are used by
/// ``RSVPEngine`` to modulate per-word display duration.
enum WordComplexityAnalyzer {

    /// Analyzes an array of words and returns a parallel array of complexity scores.
    /// - Parameter words: The tokenized word array (same format stored in ``WordStorage``).
    /// - Returns: A `[Float]` array of the same length, each value in 0.0…1.0.
    nonisolated static func analyzeComplexity(_ words: [String]) -> [Float] {
        guard !words.isEmpty else { return [] }

        // Reconstruct text for NLTagger context
        let joinedText = words.joined(separator: " ")

        // Tag lexical classes
        let lexicalTags = tagLexicalClasses(text: joinedText, wordCount: words.count)

        // Tag named entities
        let entityTags = tagNamedEntities(text: joinedText, wordCount: words.count)

        var scores = [Float](repeating: 0.5, count: words.count)

        for i in 0..<words.count {
            let word = words[i]
            let stripped = word.trimmingCharacters(in: .punctuationCharacters)

            // Skip empty or punctuation-only tokens
            guard !stripped.isEmpty else {
                scores[i] = 0.1
                continue
            }

            // Check if word is CJK-dominant — use simplified scoring
            if isCJKDominant(stripped) {
                scores[i] = cjkComplexity(stripped)
                continue
            }

            var score: Double = 0

            // 1. Word length (weight 0.15)
            let lengthScore = min(Double(stripped.count) / 12.0, 1.0)
            score += lengthScore * 0.15

            // 2. Lexical class (weight 0.25)
            let lexicalTag: NLTag? = lexicalTags[safe: i] ?? nil
            let lexicalScore = lexicalClassScore(lexicalTag)
            score += lexicalScore * 0.25

            // 3. Frequency — common word detection (weight 0.35)
            let isCommon = commonWords.contains(stripped.lowercased())
            let frequencyScore: Double = isCommon ? 0.0 : 0.7
            score += frequencyScore * 0.35

            // 4. Named entity (weight 0.10)
            let entityTag: NLTag? = entityTags[safe: i] ?? nil
            let entityScore = namedEntityScore(entityTag)
            score += entityScore * 0.10

            // 5. Character composition (weight 0.15)
            let compositionScore = characterCompositionScore(word)
            score += compositionScore * 0.15

            scores[i] = Float(min(max(score, 0), 1))
        }

        return scores
    }

    // MARK: - NLTagger

    /// Tags the full text with lexical classes and maps results back to word indices.
    private nonisolated static func tagLexicalClasses(text: String, wordCount: Int) -> [NLTag?] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        return extractTags(from: tagger, scheme: .lexicalClass, text: text, wordCount: wordCount)
    }

    /// Tags the full text with name types and maps results back to word indices.
    private nonisolated static func tagNamedEntities(text: String, wordCount: Int) -> [NLTag?] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        return extractTags(from: tagger, scheme: .nameType, text: text, wordCount: wordCount)
    }

    /// Walks through the tagger output and assigns one tag per word by matching
    /// space-separated boundaries in the joined text.
    private nonisolated static func extractTags(
        from tagger: NLTagger,
        scheme: NLTagScheme,
        text: String,
        wordCount: Int
    ) -> [NLTag?] {
        var tags = [NLTag?](repeating: nil, count: wordCount)
        var wordIndex = 0

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: scheme,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            // Find which word index this range corresponds to by counting spaces
            // before this range in the original text
            if wordIndex < wordCount {
                tags[wordIndex] = tag
                wordIndex += 1
            }
            return wordIndex < wordCount
        }

        return tags
    }

    // MARK: - Scoring helpers

    /// Maps an NLTag lexical class to a cognitive load score (0.0–1.0).
    private nonisolated static func lexicalClassScore(_ tag: NLTag?) -> Double {
        guard let tag else { return 0.5 }
        switch tag {
        case .determiner, .particle, .preposition, .conjunction:
            return 0.05  // function words — near-automatic processing
        case .pronoun:
            return 0.15
        case .verb:
            return 0.45
        case .noun:
            return 0.55
        case .adjective:
            return 0.50
        case .adverb:
            return 0.45
        case .number:
            return 0.60
        case .interjection:
            return 0.30
        default:
            return 0.65  // unknown/other — likely domain-specific
        }
    }

    /// Maps an NLTag name type to a score (0.0–1.0).
    private nonisolated static func namedEntityScore(_ tag: NLTag?) -> Double {
        guard let tag else { return 0.3 }
        switch tag {
        case .personalName:
            return 0.6
        case .placeName:
            return 0.5
        case .organizationName:
            return 0.7
        default:
            return 0.3
        }
    }

    /// Scores words with unusual character composition higher.
    private nonisolated static func characterCompositionScore(_ word: String) -> Double {
        var score = 0.0

        let hasDigit = word.unicodeScalars.contains { $0.properties.numericType != nil }
        if hasDigit { score += 0.4 }

        // Mixed case like "iPhone", "APIs", "NATO"
        let letters = word.filter(\.isLetter)
        if letters.count >= 2 {
            let hasUpper = letters.contains(where: \.isUppercase)
            let hasLower = letters.contains(where: \.isLowercase)
            let startsLower = letters.first?.isLowercase == true
            if hasUpper && hasLower && startsLower {
                score += 0.3  // camelCase like "iPhone"
            }
        }

        // Hyphens within the word
        if word.contains("-") { score += 0.2 }

        return min(score, 1.0)
    }

    /// Simplified complexity for CJK characters (length-based since NLTagger
    /// lexical class tagging is less informative for CJK tokens).
    private nonisolated static func cjkComplexity(_ word: String) -> Float {
        // CJK words are typically 1-4 characters; longer = more complex
        let length = word.count
        switch length {
        case 1: return 0.35
        case 2: return 0.45
        case 3: return 0.55
        default: return 0.65
        }
    }

    /// Returns true if the majority of characters are CJK.
    private nonisolated static func isCJKDominant(_ word: String) -> Bool {
        var cjkCount = 0
        var totalCount = 0
        for scalar in word.unicodeScalars {
            totalCount += 1
            let v = scalar.value
            if (v >= 0x4E00 && v <= 0x9FFF)
                || (v >= 0x3400 && v <= 0x4DBF)
                || (v >= 0xF900 && v <= 0xFAFF)
                || (v >= 0x20000 && v <= 0x2A6DF)
                || (v >= 0x3040 && v <= 0x30FF) {
                cjkCount += 1
            }
        }
        return totalCount > 0 && cjkCount > totalCount / 2
    }

    // MARK: - Common words

    /// The ~300 most frequent English words. Words in this set get minimal
    /// display time since readers process them almost automatically.
    private nonisolated static let commonWords: Set<String> = [
        // Articles & determiners
        "a", "an", "the", "this", "that", "these", "those", "my", "your", "his",
        "her", "its", "our", "their", "some", "any", "no", "every", "each", "all",
        "both", "few", "more", "most", "other", "such",
        // Pronouns
        "i", "me", "we", "us", "you", "he", "him", "she", "it", "they", "them",
        "who", "whom", "what", "which", "myself", "yourself", "himself", "herself",
        "itself", "ourselves", "themselves",
        // Prepositions
        "in", "on", "at", "to", "for", "with", "by", "from", "of", "about",
        "into", "through", "during", "before", "after", "above", "below", "between",
        "under", "over", "up", "down", "out", "off", "near", "against", "along",
        "around", "among", "beyond", "within", "without", "upon", "across",
        // Conjunctions
        "and", "but", "or", "nor", "so", "yet", "if", "when", "while", "because",
        "although", "since", "unless", "until", "than", "as", "whether",
        // Common verbs
        "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having",
        "do", "does", "did", "doing", "done",
        "will", "would", "shall", "should", "may", "might", "can", "could", "must",
        "get", "got", "go", "went", "gone", "come", "came", "make", "made",
        "take", "took", "taken", "give", "gave", "given",
        "say", "said", "tell", "told", "see", "saw", "seen",
        "know", "knew", "known", "think", "thought",
        "find", "found", "want", "let", "put", "set", "seem",
        "keep", "kept", "leave", "left", "begin", "began",
        "show", "showed", "shown", "try", "tried",
        "ask", "asked", "need", "feel", "felt", "become", "became",
        "use", "used", "work", "worked", "call", "called",
        "look", "looked", "turn", "turned", "help", "helped",
        "start", "started", "run", "ran", "move", "moved",
        "live", "lived", "believe", "hold", "held", "bring", "brought",
        "happen", "happened", "write", "wrote", "written",
        "sit", "sat", "stand", "stood", "play", "played",
        "read", "hear", "heard", "lose", "lost", "pay", "paid",
        "meet", "met", "include", "included", "continue", "continued",
        // Common adjectives & adverbs
        "not", "very", "also", "just", "only", "even", "still", "already",
        "now", "then", "here", "there", "where", "how", "why",
        "well", "much", "many", "often", "always", "never", "ever",
        "too", "quite", "rather", "really", "almost", "enough",
        "again", "once", "far", "long", "little", "big", "small",
        "good", "great", "new", "old", "first", "last", "next",
        "right", "own", "same", "different", "large", "early", "young",
        "important", "public", "bad", "real", "best", "high", "low",
        // Common nouns
        "time", "year", "people", "way", "day", "man", "woman", "child",
        "world", "life", "hand", "part", "place", "case", "week",
        "thing", "name", "fact", "point", "end", "home", "line",
        "number", "head", "house", "side", "group", "problem", "word",
        // Other function words
        "not", "like", "back", "one", "two", "three", "four", "five",
        "able", "may", "might", "else", "however", "though", "perhaps",
    ]
}

// MARK: - Safe array subscript

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
