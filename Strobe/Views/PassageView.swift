import SwiftUI
import SwiftData

/// Full-screen passage view shown over the reader when the user wants to
/// "find their place." Renders every word as a tappable view in a flowing
/// layout, highlights the current reading position, and supports in-text
/// search with previous/next match navigation. Tapping a word seeks the
/// `RSVPEngine` to that index without dismissing the view, so the user
/// can keep browsing.
struct PassageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var document: Document
    let engine: RSVPEngine
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    /// Number of words bundled into a single `WordChunkView`. Chunks live in a
    /// `LazyVStack` so very long documents only render visible regions.
    /// Internal access lets `@testable` cover the chunk math helpers below.
    static let chunkSize = 200

    @State private var searchQuery: String = ""
    @State private var matchIndices: [Int] = []
    /// Mirror of `matchIndices` for O(1) per-word lookups; kept in sync wherever
    /// `matchIndices` is assigned so chunk renders don't rebuild a Set.
    @State private var matchSet: Set<Int> = []
    @State private var currentMatchPosition: Int = 0
    @State private var renderedChunks: Set<Int> = []
    @State private var pendingWordScroll: PendingWordScroll?
    /// Lazily-built lowercased copy of `words`, computed off-main on first
    /// search so each keystroke doesn't re-lowercase the whole document.
    @State private var lowercasedWords: [String]?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    /// A word-center scroll that's waiting for its containing chunk to be
    /// realized. Consumed by the `renderedChunks` `onChange` handler in the
    /// passage scroll body.
    private struct PendingWordScroll {
        let target: Int
        let animated: Bool
    }

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 720 : .infinity
    }

    private var words: [String] {
        engine.words
    }

    private var chunkCount: Int {
        Self.chunkCount(wordCount: words.count)
    }

    private func chunkRange(_ chunkIndex: Int) -> Range<Int> {
        Self.chunkRange(chunkIndex: chunkIndex, wordCount: words.count)
    }

    private func chunkIndex(for wordIndex: Int) -> Int {
        Self.chunkIndex(for: wordIndex, wordCount: words.count)
    }

    /// Stable scroll id for an individual word. Distinct namespace from the
    /// `LazyVStack` chunk ids (plain `Int`) so they can't collide.
    fileprivate static func wordScrollID(_ wordIndex: Int) -> String {
        "word-\(wordIndex)"
    }

    private var currentMatchWord: Int? {
        guard !matchIndices.isEmpty, currentMatchPosition < matchIndices.count else { return nil }
        return matchIndices[currentMatchPosition]
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchBar
                if !searchQuery.isEmpty {
                    searchNav
                }
                passageScroll
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        #endif
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(readerFont.boldFont(size: 18))
                    .foregroundStyle(StrobeTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(engine.currentIndex + 1) / \(words.count)")
                    .font(readerFont.regularFont(size: 12))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(readerFont.boldFont(size: 16))
                    .foregroundStyle(StrobeTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .accessibilityHint("Close text view")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Circular floating action button overlaid on the lower-right of the
    /// scroll. Publishes via `scrollIntent` so the actual `scrollTo` runs
    /// inside the `ScrollViewReader` closure that owns the proxy.
    private var floatingFocusButton: some View {
        Button {
            scrollIntent = .currentWord
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StrobeTheme.accent)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(StrobeTheme.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Center on current word")
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(StrobeTheme.textSecondary)
                .font(.system(size: 14, weight: .semibold))

            TextField("Search text", text: $searchQuery)
                .font(readerFont.regularFont(size: 15))
                .foregroundStyle(StrobeTheme.textPrimary)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                #endif
                .onSubmit {
                    if !matchIndices.isEmpty {
                        stepMatch(by: 1)
                    }
                }
                .onChange(of: searchQuery) { _, _ in
                    runSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchTask?.cancel()
                    searchQuery = ""
                    matchIndices = []
                    matchSet = []
                    currentMatchPosition = 0
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
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var searchNav: some View {
        HStack(spacing: 12) {
            Text(matchCountLabel)
                .font(readerFont.regularFont(size: 13))
                .foregroundStyle(matchIndices.isEmpty ? StrobeTheme.textSecondary.opacity(0.6) : StrobeTheme.textSecondary)

            Spacer()

            Button {
                stepMatch(by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(matchIndices.isEmpty ? StrobeTheme.textSecondary.opacity(0.4) : StrobeTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(matchIndices.isEmpty)
            .accessibilityLabel("Previous match")

            Button {
                stepMatch(by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(matchIndices.isEmpty ? StrobeTheme.textSecondary.opacity(0.4) : StrobeTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(matchIndices.isEmpty)
            .accessibilityLabel("Next match")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var matchCountLabel: String {
        if matchIndices.isEmpty {
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return q.isEmpty ? "" : "No matches"
        }
        return "\(currentMatchPosition + 1) of \(matchIndices.count)"
    }

    // MARK: - Scroll intent
    //
    // SwiftUI's `ScrollViewProxy` can only be used inside a `ScrollViewReader`'s
    // closure. We publish "scroll requests" from buttons / search nav into this
    // state and have a single `onChange` inside the reader actually issue the
    // scrollTo. Nil after the scroll has been consumed.
    enum ScrollIntent: Equatable {
        case currentWord
        case matchPosition(Int)
    }
    @State private var scrollIntent: ScrollIntent?

    // MARK: - Passage scroll

    @ViewBuilder
    private var passageScroll: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<chunkCount, id: \.self) { idx in
                            WordChunkView(
                                words: words,
                                range: chunkRange(idx),
                                currentIndex: engine.currentIndex,
                                matchSet: matchSet,
                                currentMatchWord: currentMatchWord,
                                font: readerFont,
                                onTap: handleWordTap
                            )
                            .id(idx)
                            .padding(.horizontal, 18)
                            .onAppear { renderedChunks.insert(idx) }
                            .onDisappear { renderedChunks.remove(idx) }
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .mask(edgeFadeMask)
                .onAppear {
                    performScroll(.currentWord, proxy: proxy, animated: false)
                }
                .onChange(of: scrollIntent) { _, intent in
                    guard let intent else { return }
                    performScroll(intent, proxy: proxy, animated: true)
                    scrollIntent = nil
                }
                .onChange(of: renderedChunks) { _, newChunks in
                    guard let pending = pendingWordScroll,
                          newChunks.contains(chunkIndex(for: pending.target)) else { return }
                    pendingWordScroll = nil
                    scrollToWord(pending.target, proxy: proxy, animated: pending.animated)
                }
            }

            floatingFocusButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
    }

    /// Top + bottom alpha fade applied to the passage scroll so words ease
    /// in/out of the viewport instead of being abruptly clipped. Mask values
    /// are alpha only — the actual gradient colors don't matter.
    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)

            Rectangle().fill(Color.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
        }
    }

    private func performScroll(_ intent: ScrollIntent, proxy: ScrollViewProxy, animated: Bool) {
        let targetWord: Int
        switch intent {
        case .currentWord:
            targetWord = engine.currentIndex
        case .matchPosition(let pos):
            guard !matchIndices.isEmpty, pos < matchIndices.count else { return }
            targetWord = matchIndices[pos]
        }
        let chunk = chunkIndex(for: targetWord)

        if renderedChunks.contains(chunk) {
            // Chunk is in the hierarchy — the word-level id resolves now.
            scrollToWord(targetWord, proxy: proxy, animated: animated)
        } else {
            // Off-screen target: pre-scroll to the chunk using an anchor that
            // approximates the word's vertical position within the chunk. That
            // way the pre-scroll lands close to the final centered position,
            // so the word-level fine-tune (consumed by the renderedChunks
            // onChange below) is a small smooth adjustment rather than a jump.
            pendingWordScroll = PendingWordScroll(target: targetWord, animated: animated)
            let posInChunk = CGFloat(targetWord % Self.chunkSize) / CGFloat(max(1, Self.chunkSize))
            let approxAnchor = UnitPoint(x: 0.5, y: posInChunk)
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(chunk, anchor: approxAnchor)
                }
            } else {
                proxy.scrollTo(chunk, anchor: approxAnchor)
            }
        }
    }

    private func scrollToWord(_ wordIndex: Int, proxy: ScrollViewProxy, animated: Bool) {
        let wordID = Self.wordScrollID(wordIndex)
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(wordID, anchor: .center)
            }
        } else {
            proxy.scrollTo(wordID, anchor: .center)
        }
    }

    // MARK: - Actions

    private func handleWordTap(_ index: Int) {
        guard index >= 0, index < words.count else { return }
        engine.seek(to: index)
        scrollIntent = .currentWord
        HapticManager.shared.scrubTick()
    }

    private func runSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matchIndices = []
            matchSet = []
            currentMatchPosition = 0
            return
        }

        // Debounced: scanning (and on first search, lowercasing) every word of
        // a long document per keystroke would jank typing on the main thread.
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            let lowered: [String]
            if let cached = lowercasedWords {
                lowered = cached
            } else {
                let snapshot = words
                lowered = await Task.detached(priority: .userInitiated) {
                    snapshot.map { $0.lowercased() }
                }.value
                guard !Task.isCancelled else { return }
                lowercasedWords = lowered
            }

            let results = Self.findMatches(query: query, inLowercasedWords: lowered)
            guard !Task.isCancelled, query == searchQuery else { return }
            matchIndices = results
            matchSet = Set(results)
            if results.isEmpty {
                currentMatchPosition = 0
                return
            }
            // Land on the match closest to the user's current reading position
            // so they don't get yanked far away from where they were.
            currentMatchPosition = Self.nearestMatchPosition(to: engine.currentIndex, in: results)
            scrollIntent = .matchPosition(currentMatchPosition)
        }
    }

    private func stepMatch(by delta: Int) {
        guard !matchIndices.isEmpty else { return }
        let n = matchIndices.count
        currentMatchPosition = (currentMatchPosition + delta + n) % n
        scrollIntent = .matchPosition(currentMatchPosition)
        HapticManager.shared.scrubTick()
    }

    // MARK: - Pure helpers (testable)

    /// Total number of word chunks needed to hold `wordCount` words at the
    /// given chunk size. Returns 0 for empty input.
    static func chunkCount(wordCount: Int, chunkSize: Int = PassageView.chunkSize) -> Int {
        guard wordCount > 0, chunkSize > 0 else { return 0 }
        return (wordCount + chunkSize - 1) / chunkSize
    }

    /// Half-open range of word indices contained in `chunkIndex`, clamped to
    /// `wordCount`. Empty range if the chunk index is out of bounds.
    static func chunkRange(chunkIndex: Int, wordCount: Int, chunkSize: Int = PassageView.chunkSize) -> Range<Int> {
        guard chunkIndex >= 0, chunkSize > 0 else { return 0..<0 }
        let start = chunkIndex * chunkSize
        guard start < wordCount else { return wordCount..<wordCount }
        let end = min(start + chunkSize, wordCount)
        return start..<end
    }

    /// Chunk index that contains `wordIndex`, clamped to `[0, chunkCount-1]`.
    /// Returns 0 when there are no chunks.
    static func chunkIndex(for wordIndex: Int, wordCount: Int, chunkSize: Int = PassageView.chunkSize) -> Int {
        let count = chunkCount(wordCount: wordCount, chunkSize: chunkSize)
        guard count > 0, chunkSize > 0 else { return 0 }
        return max(0, min(wordIndex / chunkSize, count - 1))
    }

    /// Case-insensitive substring search over `words`. Whitespace is trimmed
    /// from the query, and empty/whitespace-only queries yield no matches.
    /// Returned indices are sorted ascending by construction.
    static func findMatches(query: String, in words: [String]) -> [Int] {
        findMatches(query: query, inLowercasedWords: words.map { $0.lowercased() })
    }

    /// Variant of ``findMatches(query:in:)`` over pre-lowercased words, so the
    /// per-keystroke search path can reuse a cached lowercased copy instead of
    /// re-lowercasing the whole document each time.
    static func findMatches(query: String, inLowercasedWords words: [String]) -> [Int] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        var results: [Int] = []
        results.reserveCapacity(min(words.count, 256))
        for (i, word) in words.enumerated() where word.contains(needle) {
            results.append(i)
        }
        return results
    }

    /// Position into `matches` of the entry closest to `wordIndex`. Ties
    /// break toward the earlier (smaller-index) match. `matches` must be
    /// sorted ascending. Returns 0 for an empty array.
    static func nearestMatchPosition(to wordIndex: Int, in matches: [Int]) -> Int {
        guard !matches.isEmpty else { return 0 }
        var lo = 0
        var hi = matches.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if matches[mid] < wordIndex { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return 0 }
        if lo == matches.count { return matches.count - 1 }
        let prevDelta = abs(matches[lo - 1] - wordIndex)
        let nextDelta = abs(matches[lo] - wordIndex)
        return prevDelta <= nextDelta ? lo - 1 : lo
    }
}

// MARK: - Word chunk

/// Renders a contiguous slice of words in a flowing layout. Lifted out of
/// `PassageView` so SwiftUI can diff and re-render chunks independently,
/// keeping per-tap rerenders cheap on long documents.
private struct WordChunkView: View {
    let words: [String]
    let range: Range<Int>
    let currentIndex: Int
    let matchSet: Set<Int>
    let currentMatchWord: Int?
    let font: ReaderFont
    let onTap: (Int) -> Void

    var body: some View {
        WordFlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(range, id: \.self) { i in
                WordToken(
                    text: words[i],
                    isCurrent: i == currentIndex,
                    isPrimaryMatch: i == currentMatchWord,
                    isMatch: matchSet.contains(i),
                    font: font
                ) {
                    onTap(i)
                }
                .id(PassageView.wordScrollID(i))
            }
        }
    }
}

/// A single tappable word in the passage view. Visually conveys three states:
/// the current reading position (red fill), the active search match (solid
/// yellow), and any other search match (faded yellow).
private struct WordToken: View {
    let text: String
    let isCurrent: Bool
    let isPrimaryMatch: Bool
    let isMatch: Bool
    let font: ReaderFont
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(font.regularFont(size: 18))
                .foregroundStyle(textColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint(isCurrent ? "Current word" : "Tap to jump here")
    }

    private var textColor: Color {
        if isCurrent { return .white }
        if isPrimaryMatch { return .black }
        return StrobeTheme.textPrimary
    }

    private var backgroundColor: Color {
        if isCurrent { return StrobeTheme.accent }
        if isPrimaryMatch { return Color.yellow.opacity(0.9) }
        if isMatch { return Color.yellow.opacity(0.28) }
        return .clear
    }
}

// MARK: - Flow layout

/// Wraps a row of words across multiple lines, sized by each subview's
/// intrinsic width. Designed for the passage view; not a general-purpose
/// flow layout (e.g., it doesn't support RTL or vertical alignment options).
private struct WordFlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(subviews: subviews, in: width)
        return CGSize(width: width.isFinite ? width : result.maxLineWidth, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private struct Arrangement {
        var frames: [CGRect]
        var height: CGFloat
        var maxLineWidth: CGFloat
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> Arrangement {
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        return Arrangement(frames: frames, height: y + lineHeight, maxLineWidth: maxLineWidth)
    }
}
