import Foundation

/// Decides when to ask for an App Store rating, so the prompt only reaches
/// people who have been reading.
///
/// A day becomes a reading day once playback has shown
/// ``wordsPerReadingDay`` words on it. The prompt is due on a reading day
/// after ``readingDaysBeforePrompt`` of them, at most once per app version
/// and no sooner than ``minimumDaysBetweenPrompts`` after the last ask.
/// Asking starts the reading-day count over. The system shows its prompt at
/// most three times a year and may show nothing; this only decides when the
/// app asks.
///
/// Kept in UserDefaults on the device; nothing is sent anywhere.
nonisolated struct ReviewPrompt: Codable, Equatable {
    static let wordsPerReadingDay = 500
    static let readingDaysBeforePrompt = 3
    static let minimumDaysBetweenPrompts = 60

    static let storageKey = "reviewPrompt"

    /// Reading days since the last ask, or ever before the first.
    private(set) var readingDays = 0
    /// The start of the day `wordsOnDay` counts.
    private(set) var day: Date?
    private(set) var wordsOnDay = 0
    private(set) var lastPromptDate: Date?
    private(set) var lastPromptVersion: String?

    /// Adds words shown by playback to the count for `date`'s day.
    mutating func recordWordsRead(_ count: Int, at date: Date, calendar: Calendar = .current) {
        guard count > 0 else { return }
        let today = calendar.startOfDay(for: date)
        if day != today {
            day = today
            wordsOnDay = 0
        }
        let wasReadingDay = wordsOnDay >= Self.wordsPerReadingDay
        wordsOnDay += count
        if !wasReadingDay && wordsOnDay >= Self.wordsPerReadingDay {
            readingDays += 1
        }
    }

    func isDue(at date: Date, appVersion: String, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: date)
        guard readingDays >= Self.readingDaysBeforePrompt,
              day == today, wordsOnDay >= Self.wordsPerReadingDay,
              appVersion != lastPromptVersion else { return false }
        guard let lastPromptDate else { return true }
        let daysSince = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: lastPromptDate), to: today
        ).day ?? 0
        return daysSince >= Self.minimumDaysBetweenPrompts
    }

    mutating func recordPrompt(at date: Date, appVersion: String) {
        lastPromptDate = date
        lastPromptVersion = appVersion
        readingDays = 0
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The saved state, or a fresh one if none is saved or it can't be read.
    static func load(from defaults: UserDefaults = .standard) -> ReviewPrompt {
        guard let data = defaults.data(forKey: storageKey),
              let prompt = try? JSONDecoder().decode(ReviewPrompt.self, from: data) else {
            return ReviewPrompt()
        }
        return prompt
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Loads the saved state, applies `change`, and saves the result.
    static func update(in defaults: UserDefaults = .standard, _ change: (inout ReviewPrompt) -> Void) {
        var prompt = load(from: defaults)
        change(&prompt)
        prompt.save(to: defaults)
    }
}
