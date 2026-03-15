import SwiftUI

/// Full-screen onboarding tutorial shown on first launch.
/// A paged walkthrough introducing import, reading controls, chapters, and settings.
struct TutorialView: View {
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentPage = 0

    private let pageCount = 5

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            #if os(iOS)
            TabView(selection: $currentPage) {
                ForEach(0..<pageCount, id: \.self) { index in
                    pageContent(for: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #else
            VStack {
                pageContent(for: currentPage)

                macOSNavigation
                    .padding(.bottom, 32)
            }
            #endif
        }
    }

    // MARK: - Page data

    private func pageContent(for index: Int) -> some View {
        switch index {
        case 0:
            page(icon: "book.pages.fill", title: "Welcome to Strobe",
                 description: "Speed read one word at a time, faster than ever.")
        case 1:
            page(icon: "plus.circle.fill", title: "Import Your Books",
                 description: "Click the + button to import PDFs and EPUBs, or enter text directly.")
        case 2:
            page(icon: "hand.tap.fill", title: "Reading Controls",
                 description: controlsDescription)
        case 3:
            page(icon: "list.bullet.circle.fill", title: "Navigate by Chapter",
                 description: "Books with chapters show a chapter list. Track your progress as you read.")
        default:
            page(icon: "gearshape.fill", title: "Make It Yours",
                 description: "Adjust reading speed, font, text size, and smart timing in Settings.",
                 showButton: true)
        }
    }

    private var controlsDescription: String {
        #if os(macOS)
        "Press Space to read, Space to pause. Use arrow keys or trackpad to scrub through text."
        #else
        "Hold to read, release to pause. Swipe left or right to scrub through text."
        #endif
    }

    // MARK: - macOS navigation

    #if os(macOS)
    private var macOSNavigation: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation { currentPage -= 1 }
            } label: {
                Text("Back")
                    .font(StrobeTheme.bodyFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .opacity(currentPage > 0 ? 1 : 0)
            .disabled(currentPage == 0)

            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? StrobeTheme.accent : StrobeTheme.textSecondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            if currentPage < pageCount - 1 {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Next")
                        .font(StrobeTheme.bodyFont(size: 14, bold: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(StrobeTheme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    #endif

    // MARK: - Page template

    private func page(
        icon: String,
        title: String,
        description: String,
        showButton: Bool = false
    ) -> some View {
        let isPad = horizontalSizeClass == .regular
        let iconSize: CGFloat = isPad ? 100 : 80
        let titleSize: CGFloat = isPad ? 40 : 32
        let bodySize: CGFloat = isPad ? 20 : 18

        return VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(StrobeTheme.accent.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(StrobeTheme.accent)
                    .shadow(color: StrobeTheme.accent.opacity(0.5), radius: 10)
            }

            VStack(spacing: 16) {
                Text(title)
                    .font(StrobeTheme.titleFont(size: titleSize))
                    .foregroundStyle(StrobeTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(StrobeTheme.bodyFont(size: bodySize))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .lineSpacing(4)
            }

            if showButton {
                Button {
                    hasSeenTutorial = true
                    dismiss()
                } label: {
                    Text("Get Started")
                        .font(StrobeTheme.bodyFont(size: bodySize, bold: true))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(StrobeTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: StrobeTheme.accent.opacity(0.4), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            } else {
                // Placeholder to keep spacing somewhat consistent
                Spacer().frame(height: 60)
            }

            Spacer()
            Spacer()
        }
        // Constrain content to a comfortable readable column on iPad/Mac
        .frame(maxWidth: isPad ? 640 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}
