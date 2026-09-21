import SwiftUI

/// Vertical arrangement of the reader: the chrome bars pin to the top and
/// bottom of the safe area, and the word centers on a fixation line fixed to
/// the whole screen or window — not to the space the bars leave, which
/// varies with chapter navigation, Dynamic Type, and safe-area insets.
///
/// The bars keep their layout size while faded out, so nothing here changes
/// when playback starts or stops and the word holds still. The line only
/// yields when the word would run into a bar (see `fixationCenterY`).
///
/// A layout inside the safe area can't see the insets around it, so the
/// caller passes them in from a `GeometryReader`.
struct ReaderStageLayout: Layout {
    nonisolated enum Role {
        case topBar
        case bottomBar
        /// Centered on the fixation line. The default for untagged subviews.
        case fixation
        /// Centered in the space the bars leave. For content that only ever
        /// appears alongside visible bars, where the bars are what it has to
        /// look balanced against.
        case betweenBars
    }

    /// Where the fixation line sits, as a fraction of the full container
    /// height (safe-area insets included). Above 0.5 on purpose: the eye
    /// places the middle of a vertical extent a few percent above its
    /// geometric midpoint, so a word at exactly 0.5 reads as low. A fraction
    /// rather than a point offset so the bias scales from a landscape phone
    /// to a 13" iPad.
    nonisolated static let fixationFraction: CGFloat = 0.47

    var topInset: CGFloat
    var bottomInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fitting = ProposedViewSize(width: bounds.width, height: nil)
        var topBarHeight: CGFloat = 0
        var bottomBarHeight: CGFloat = 0

        for subview in subviews {
            switch subview[ReaderStageRoleKey.self] {
            case .topBar:
                topBarHeight = max(topBarHeight, subview.sizeThatFits(fitting).height)
                subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: fitting)
            case .bottomBar:
                bottomBarHeight = max(bottomBarHeight, subview.sizeThatFits(fitting).height)
                subview.place(at: CGPoint(x: bounds.midX, y: bounds.maxY), anchor: .bottom, proposal: fitting)
            case .fixation, .betweenBars:
                break
            }
        }

        // Each remaining subview is resolved on its own, so the word holds
        // its place while it cross-fades with the completion card.
        for subview in subviews {
            let centerY: CGFloat
            switch subview[ReaderStageRoleKey.self] {
            case .topBar, .bottomBar:
                continue
            case .fixation:
                centerY = Self.fixationCenterY(
                    boundsHeight: bounds.height,
                    topInset: topInset,
                    bottomInset: bottomInset,
                    contentHeight: subview.sizeThatFits(fitting).height,
                    topBarHeight: topBarHeight,
                    bottomBarHeight: bottomBarHeight
                )
            case .betweenBars:
                centerY = Self.centerBetweenBars(
                    boundsHeight: bounds.height,
                    topBarHeight: topBarHeight,
                    bottomBarHeight: bottomBarHeight
                )
            }
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY + centerY), anchor: .center, proposal: fitting)
        }
    }

    /// The y of a fixation subview's center, measured from the top of the
    /// layout's bounds (the safe area).
    ///
    /// Ideally that is the fixation line. If the content would overlap a bar
    /// there, it moves the minimum distance that clears it; if it can't fit
    /// between the bars at all, it centers between them so the overlap is
    /// split evenly.
    nonisolated static func fixationCenterY(
        boundsHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentHeight: CGFloat,
        topBarHeight: CGFloat,
        bottomBarHeight: CGFloat
    ) -> CGFloat {
        let containerHeight = topInset + boundsHeight + bottomInset
        let line = containerHeight * fixationFraction - topInset
        let highest = topBarHeight + contentHeight / 2
        let lowest = boundsHeight - bottomBarHeight - contentHeight / 2
        guard highest <= lowest else {
            return centerBetweenBars(
                boundsHeight: boundsHeight,
                topBarHeight: topBarHeight,
                bottomBarHeight: bottomBarHeight
            )
        }
        return min(max(line, highest), lowest)
    }

    /// The midpoint of the space the bars leave, measured from the top of
    /// the layout's bounds.
    nonisolated static func centerBetweenBars(
        boundsHeight: CGFloat,
        topBarHeight: CGFloat,
        bottomBarHeight: CGFloat
    ) -> CGFloat {
        (topBarHeight + boundsHeight - bottomBarHeight) / 2
    }
}

nonisolated private struct ReaderStageRoleKey: LayoutValueKey {
    static let defaultValue: ReaderStageLayout.Role = .fixation
}

extension View {
    func readerStageRole(_ role: ReaderStageLayout.Role) -> some View {
        layoutValue(key: ReaderStageRoleKey.self, value: role)
    }
}
