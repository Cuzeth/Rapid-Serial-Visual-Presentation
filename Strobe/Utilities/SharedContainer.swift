import Foundation

/// The App Group the app shares with its extensions: one directory and one
/// UserDefaults suite that the app, the share extension, and the widget can
/// all read and write.
///
/// Compiled into every target that uses the group, so it stays free of
/// app-only types.
nonisolated enum SharedContainer {
    /// The App Group identifier, the same on iOS and macOS.
    static let appGroupID = "group.com.abdeen.strobe"

    /// The group's shared directory, or nil when the build isn't entitled to
    /// the group (an unsigned build, for example).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// The group's shared defaults.
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}
