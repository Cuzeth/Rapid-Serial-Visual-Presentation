import SwiftUI

/// Full-screen onboarding tutorial shown on first launch.
/// A paged walkthrough introducing import, reading controls, chapters, and settings.
struct TutorialView: View {
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                page(
                    icon: "book.pages.fill",
                    title: "Welcome to Strobe",
                    description: "Speed read one word at a time, faster than ever."
                ).tag(0)

                page(
                    icon: "plus.circle.fill",
                    title: "Import Your Books",
                    description: "Tap the + button to import PDFs and EPUBs from Files or iCloud Drive."
                ).tag(1)

                page(
                    icon: "hand.tap.fill",
                    title: "Reading Controls",
                    description: "Hold to read, release to pause. Swipe left or right to scrub through text."
                ).tag(2)

                page(
                    icon: "list.bullet.circle.fill",
                    title: "Navigate by Chapter",
                    description: "Books with chapters show a chapter list. Track your progress as you read."
                ).tag(3)

                page(
                    icon: "gearshape.fill",
                    title: "Make It Yours",
                    description: "Adjust reading speed, font, text size, and smart timing in Settings.",
                    showButton: true
                ).tag(4)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    // MARK: - Page template

    private func page(
        icon: String,
        title: String,
        description: String,
        showButton: Bool = false
    ) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(StrobeTheme.accent.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
                
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundStyle(StrobeTheme.accent)
                    .shadow(color: StrobeTheme.accent.opacity(0.5), radius: 10)
            }

            VStack(spacing: 16) {
                Text(title)
                    .font(StrobeTheme.titleFont(size: 32))
                    .foregroundStyle(StrobeTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(StrobeTheme.bodyFont(size: 18))
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
                        .font(StrobeTheme.bodyFont(size: 18, bold: true))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(StrobeTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: StrobeTheme.accent.opacity(0.4), radius: 10, y: 5)
                }
                .padding(.top, 24)
            } else {
                // Placeholder to keep spacing somewhat consistent
                Spacer().frame(height: 60)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
