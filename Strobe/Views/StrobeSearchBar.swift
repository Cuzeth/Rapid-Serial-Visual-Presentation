import SwiftUI

/// Shared search-bar chrome: magnifying-glass icon, plain text field, and a
/// clear button inside a `StrobeTheme.surface` rounded rect.
///
/// The bare `TextField` is handed to `configureField` so each call site can
/// attach its own focus, submit handling, and platform input modifiers
/// without this component needing to know about them.
struct StrobeSearchBar<Field: View>: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    /// Runs when the clear button is tapped. Defaults to clearing `text`;
    /// call sites with extra search state to reset pass their own action.
    var onClear: (() -> Void)? = nil
    @ViewBuilder let configureField: (TextField<Text>) -> Field

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(StrobeTheme.textSecondary)
                .font(.system(size: 14, weight: .semibold))

            configureField(TextField(placeholder, text: $text))
                .font(font)
                .foregroundStyle(StrobeTheme.textPrimary)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    if let onClear {
                        onClear()
                    } else {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StrobeTheme.textSecondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StrobeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
