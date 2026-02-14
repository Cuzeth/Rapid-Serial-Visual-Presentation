import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        lightImpact.prepare()
        softImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    /// Finger down (play) or finger up (pause)
    func playPause() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// Each word change during scrubbing
    func scrubTick() {
        softImpact.impactOccurred(intensity: 0.5)
        softImpact.prepare()
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
