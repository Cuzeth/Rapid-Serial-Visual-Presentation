import SwiftUI

/// Icon-in-a-circle button chrome shared by the reader, chapter list,
/// settings, and text-entry headers — previously hand-rolled at each site.
struct CircleIconButton: View {
    let systemImage: String
    var iconSize: CGFloat = 18
    var padding: CGFloat = 12
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(StrobeTheme.textSecondary)
                .padding(padding)
                .background(StrobeTheme.surface)
                .clipShape(Circle())
                // Circles this size sit just under the 44pt minimum tap
                // target; extend the hit area without changing the look.
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
