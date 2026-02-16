import SwiftUI

struct TutorialView: View {
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
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
                description: "Hold to read, let go to pause, and swipe left or right to scrub."
            ).tag(2)

            page(
                icon: "list.bullet.circle.fill",
                title: "Navigate by Chapter",
                description: "Books with chapters show a chapter list. Track your progress as you read."
            ).tag(3)

            page(
                icon: "gearshape.fill",
                title: "Make It Yours",
                description: "Adjust reading speed, font, text size, smart timing, and appearance in Settings.",
                showButton: true
            ).tag(4)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Page template

    private func page(
        icon: String,
        title: String,
        description: String,
        showButton: Bool = false
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text(title)
                .font(readerFont.boldFont(size: 28))
                .multilineTextAlignment(.center)

            Text(description)
                .font(readerFont.regularFont(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if showButton {
                Button {
                    hasSeenTutorial = true
                    dismiss()
                } label: {
                    Text("Get Started")
                        .font(readerFont.regularFont(size: 16))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
