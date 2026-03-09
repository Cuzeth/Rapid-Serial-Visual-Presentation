import UIKit

/// Provides haptic feedback for reading interactions.
///
/// Uses pre-prepared feedback generators for minimal latency.
/// Each method fires its feedback and immediately re-prepares for the next use.
final class HapticManager {
    static let shared = HapticManager()

    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        mediumImpact.prepare()
        lightImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    /// Finger down (play) or finger up (pause)
    func playPause() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Each word change during scrubbing
    func scrubTick() {
        lightImpact.impactOccurred(intensity: 0.7)
        lightImpact.prepare()
    }

    /// Hit the beginning or end while scrubbing
    func scrubBoundary() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    /// WPM slider snapped to a new value
    func wpmChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// Reached the end of the text during playback
    func completedReading() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }
}
