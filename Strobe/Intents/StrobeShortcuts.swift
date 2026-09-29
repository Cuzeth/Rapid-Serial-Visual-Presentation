import AppIntents

/// The shortcuts Strobe offers with no setup, in Siri, Spotlight, the
/// Shortcuts app, and on the Action button. Speed Read Text takes text, so
/// it's an action for building shortcuts instead.
struct StrobeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "Resume reading in \(.applicationName)",
                "Pick up where I left off in \(.applicationName)",
            ],
            shortTitle: "Continue Reading",
            systemImageName: "book"
        )
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Read \(\.$target) in \(.applicationName)",
                "Open a document in \(.applicationName)",
            ],
            shortTitle: "Open Document",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: GetReadingProgressIntent(),
            phrases: [
                "How far am I in \(.applicationName)",
                "Get my reading progress in \(.applicationName)",
                "How much do I have left in \(.applicationName)",
            ],
            shortTitle: "Reading Progress",
            systemImageName: "percent"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .red
}
