import Foundation

/// The kind of file a document came from, as its cover labels it.
nonisolated enum DocumentKind: Equatable {
    case epub
    case pdf
    case text

    /// Reads the kind from the stored file name. Pasted text stores its title
    /// as the file name, so anything without a known extension is text.
    init(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        default: self = .text
        }
    }

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .text: "TEXT"
        }
    }
}

/// How far along a document is, as the library shows it.
nonisolated enum ReadingStatus: Equatable {
    case new
    /// A whole percentage, at least 1 so a started document never reads 0%.
    case inProgress(percent: Int)
    case finished

    init(progress: Double) {
        if progress >= 1 {
            self = .finished
        } else if progress <= 0 {
            self = .new
        } else {
            self = .inProgress(percent: max(1, Int(progress * 100)))
        }
    }

    var label: String {
        switch self {
        case .new: "New"
        case .inProgress(let percent): "\(percent)%"
        case .finished: "Finished"
        }
    }

    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
}

/// Reading-time estimates at a plain words-per-minute rate, before smart
/// timing, pauses, or complexity adjust individual words.
nonisolated enum ReadingTime {
    /// Whole minutes to read `words` words, rounded up so any remaining
    /// text counts as at least a minute.
    static func minutes(words: Int, wordsPerMinute: Int) -> Int {
        guard words > 0, wordsPerMinute > 0 else { return 0 }
        return (words + wordsPerMinute - 1) / wordsPerMinute
    }

    /// A duration such as "7 hr 38 min" or "12 min".
    static func label(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        format(minutes: minutes, width: .abbreviated, locale: locale)
    }

    /// The same duration spelled out for VoiceOver: "7 hours 38 minutes".
    static func spokenLabel(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        format(minutes: minutes, width: .wide, locale: locale)
    }

    private static func format(
        minutes: Int,
        width: Measurement<UnitDuration>.FormatStyle.UnitWidth,
        locale: Locale
    ) -> String {
        let total = max(1, minutes)
        let hours = total / 60
        let remainder = total % 60
        let style = Measurement<UnitDuration>.FormatStyle(width: width, locale: locale, usage: .asProvided)
        var parts: [String] = []
        if hours > 0 {
            parts.append(style.format(Measurement(value: Double(hours), unit: .hours)))
        }
        if remainder > 0 || hours == 0 {
            parts.append(style.format(Measurement(value: Double(remainder), unit: .minutes)))
        }
        return parts.joined(separator: " ")
    }
}

extension Document {
    var progressPercentage: Int {
        Int(progress * 100)
    }

    var kind: DocumentKind {
        DocumentKind(fileName: fileName)
    }

    var readingStatus: ReadingStatus {
        ReadingStatus(progress: progress)
    }

    /// Words after the resume position.
    var remainingWordCount: Int {
        max(0, wordCount - 1 - currentWordIndex)
    }

    /// Minutes to finish from the resume position at the document's speed.
    var remainingMinutes: Int {
        ReadingTime.minutes(words: remainingWordCount, wordsPerMinute: wordsPerMinute)
    }
}
