import SwiftUI

/// The fill behind the reading surface: the RSVP reader, the passage view,
/// the reader's chapter picker, and the settings swatches that preview them.
///
/// `trueBlack` is pure `#000000`, which leaves OLED pixels unlit. App chrome
/// outside the reading surface stays on `StrobeTheme` either way.
nonisolated enum ReaderBackground: Equatable {
    case standard
    case trueBlack

    /// Resolves the stored `trueBlackBackgroundEnabled` setting to a background.
    static func resolve(trueBlackEnabled: Bool) -> ReaderBackground {
        trueBlackEnabled ? .trueBlack : .standard
    }
}

/// Paints the current ``ReaderBackground``. Reading surfaces use this instead
/// of a `StrobeTheme` background so they all follow the setting.
struct ReaderBackdrop: View {
    @AppStorage(ReaderSettings.Keys.trueBlackBackgroundEnabled) private var trueBlackBackgroundEnabled: Bool = ReaderSettings.Defaults.trueBlackBackgroundEnabled

    var body: some View {
        switch ReaderBackground.resolve(trueBlackEnabled: trueBlackBackgroundEnabled) {
        case .standard:
            StrobeTheme.Gradients.mainBackground
        case .trueBlack:
            Color.black
        }
    }
}
