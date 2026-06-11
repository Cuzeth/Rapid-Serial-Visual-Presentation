import Foundation

/// Single source of truth for the reader's UserDefaults-backed settings:
/// key strings, default values, and a snapshot helper for contexts where
/// `@AppStorage` isn't available (e.g. `View` initializers).
///
/// Every `@AppStorage` declaration for these settings must reference
/// ``Keys`` and ``Defaults`` so a key or default can never drift between
/// the settings UI, the reader, and the engine bootstrap.
enum ReaderSettings {

    enum Keys {
        nonisolated static let defaultWPM = "defaultWPM"
        nonisolated static let fontSize = "fontSize"
        nonisolated static let smartTimingEnabled = "smartTimingEnabled"
        nonisolated static let sentencePauseEnabled = "sentencePauseEnabled"
        nonisolated static let smartTimingPercentPerLetter = "smartTimingPercentPerLetter"
        nonisolated static let sentencePauseMultiplier = "sentencePauseMultiplier"
        nonisolated static let complexityTimingEnabled = "complexityTimingEnabled"
        nonisolated static let complexityIntensity = "complexityIntensity"
        nonisolated static let holdToReadEnabled = "holdToReadEnabled"
    }

    enum Defaults {
        nonisolated static let defaultWPM = 300
        nonisolated static let fontSize = 40
        nonisolated static let smartTimingEnabled = false
        nonisolated static let sentencePauseEnabled = false
        nonisolated static let smartTimingPercentPerLetter = 4.0
        nonisolated static let sentencePauseMultiplier = 1.5
        nonisolated static let complexityTimingEnabled = false
        nonisolated static let complexityIntensity = 0.5
        nonisolated static let holdToReadEnabled = true
    }

    /// The engine-relevant timing settings, read directly from UserDefaults.
    struct TimingSnapshot {
        let smartTimingEnabled: Bool
        let sentencePauseEnabled: Bool
        let smartTimingPercentPerLetter: Double
        let sentencePauseMultiplier: Double
        let complexityTimingEnabled: Bool
        let complexityIntensity: Double
    }

    /// Reads the current timing settings for constructing an ``RSVPEngine``.
    nonisolated static func timingSnapshot(from defaults: UserDefaults = .standard) -> TimingSnapshot {
        TimingSnapshot(
            smartTimingEnabled: defaults.object(forKey: Keys.smartTimingEnabled) as? Bool
                ?? Defaults.smartTimingEnabled,
            sentencePauseEnabled: defaults.object(forKey: Keys.sentencePauseEnabled) as? Bool
                ?? Defaults.sentencePauseEnabled,
            smartTimingPercentPerLetter: defaults.object(forKey: Keys.smartTimingPercentPerLetter) as? Double
                ?? Defaults.smartTimingPercentPerLetter,
            sentencePauseMultiplier: defaults.object(forKey: Keys.sentencePauseMultiplier) as? Double
                ?? Defaults.sentencePauseMultiplier,
            complexityTimingEnabled: defaults.object(forKey: Keys.complexityTimingEnabled) as? Bool
                ?? Defaults.complexityTimingEnabled,
            complexityIntensity: defaults.object(forKey: Keys.complexityIntensity) as? Double
                ?? Defaults.complexityIntensity
        )
    }
}
