import Testing
import Foundation
import SwiftUI
import CoreGraphics
@testable import Strobe

struct ContextWordsTests {

    // MARK: - Setting

    @Test func contextWordsAreOffByDefault() {
        #expect(ReaderSettings.Defaults.contextWordsEnabled == false)
    }

    // MARK: - Neighbors

    @Test func middleWordHasBothNeighbors() {
        let neighbors = ContextWords.neighbors(of: 1, in: ["reading", "the", "information"])
        #expect(neighbors == ContextWords.Neighbors(previous: "reading", next: "information"))
    }

    @Test func documentEdgesHaveOneNeighbor() {
        let words = ["Call", "me", "Ishmael."]
        #expect(ContextWords.neighbors(of: 0, in: words) == ContextWords.Neighbors(previous: nil, next: "me"))
        #expect(ContextWords.neighbors(of: 2, in: words) == ContextWords.Neighbors(previous: "me", next: nil))
    }

    @Test func singleWordAndEmptyDocumentsHaveNoNeighbors() {
        let none = ContextWords.Neighbors(previous: nil, next: nil)
        #expect(ContextWords.neighbors(of: 0, in: ["Only"]) == none)
        #expect(ContextWords.neighbors(of: 0, in: []) == none)
    }

    @Test func indexOutsideTheDocumentHasNoNeighbors() {
        let none = ContextWords.Neighbors(previous: nil, next: nil)
        #expect(ContextWords.neighbors(of: -1, in: ["a", "b"]) == none)
        #expect(ContextWords.neighbors(of: 2, in: ["a", "b"]) == none)
    }

    // MARK: - Sizing

    /// Every size the Settings text size slider offers.
    private static let textSizes = Array(stride(from: CGFloat(24), through: 72, by: 2))

    @Test func contextScalesWithTheWordAboveAFloor() throws {
        let roomy: CGFloat = 1_000
        let at40 = try #require(ContextWords.metrics(wordFontSize: 40, clearHalfHeight: roomy))
        let at72 = try #require(ContextWords.metrics(wordFontSize: 72, clearHalfHeight: roomy))
        let at24 = try #require(ContextWords.metrics(wordFontSize: 24, clearHalfHeight: roomy))
        #expect(abs(at40.fontSize - 40 * ContextWords.fontSizeRatio) < 0.001)
        #expect(abs(at72.fontSize - 72 * ContextWords.fontSizeRatio) < 0.001)
        #expect(at24.fontSize == ContextWords.preferredMinimumFontSize)
    }

    /// Whatever the room, a context slot starts past the end of the word's
    /// guide line and ends before the bar margin.
    @Test func slotsStayPastTheGuideLineAndClearOfTheBars() {
        for size in Self.textSizes {
            for room in stride(from: CGFloat(0), through: 400, by: 2.5) {
                guard let metrics = ContextWords.metrics(wordFontSize: size, clearHalfHeight: room) else { continue }
                let innerEdge = metrics.offset - metrics.slotHeight / 2
                #expect(innerEdge > size * WordView.guideLineHeightRatio / 2, "size \(size), room \(room)")
                #expect(metrics.reach <= room - ContextWords.barMargin + 0.001, "size \(size), room \(room)")
                #expect(metrics.fontSize >= ContextWords.minimumFontSize)
                #expect(metrics.fontSize <= ContextWords.preferredFontSize(wordFontSize: size))
            }
        }
    }

    @Test func tightRoomShrinksTheContextThenHidesIt() throws {
        let size: CGFloat = 40
        let full = try #require(ContextWords.metrics(wordFontSize: size, clearHalfHeight: 1_000))
        let fullRoom = full.reach + ContextWords.barMargin
        let exact = try #require(ContextWords.metrics(wordFontSize: size, clearHalfHeight: fullRoom))
        #expect(abs(exact.fontSize - full.fontSize) < 0.001)

        let minimumRoom = ContextWords.innerEdge(wordFontSize: size)
            + ContextWords.minimumFontSize * ContextWords.slotHeightRatio
            + ContextWords.barMargin
        let shrunk = try #require(ContextWords.metrics(wordFontSize: size, clearHalfHeight: (fullRoom + minimumRoom) / 2))
        #expect(shrunk.fontSize < full.fontSize)
        #expect(shrunk.fontSize > ContextWords.minimumFontSize)

        #expect(ContextWords.metrics(wordFontSize: size, clearHalfHeight: minimumRoom + 0.5) != nil)
        #expect(ContextWords.metrics(wordFontSize: size, clearHalfHeight: minimumRoom - 0.5) == nil)
        #expect(ContextWords.metrics(wordFontSize: size, clearHalfHeight: 0) == nil)
    }

    /// A slot shorter than a font's line box would shrink the context text
    /// to fit it.
    @MainActor
    @Test func slotHoldsEveryReaderFontsLineBox() {
        let size: CGFloat = 100
        for font in ReaderFont.allCases {
            let platform = font.platformFont(size: size)
            let lineBox = platform.ascender - platform.descender + platform.leading
            #expect(lineBox <= size * ContextWords.slotHeightRatio, "\(font.rawValue): \(lineBox)")
        }
    }

    // MARK: - Stage layout

    // Measured reader chrome, as in ReaderLayoutTests: the top bar and the
    // bottom bar with chapter navigation.
    private static let topBar: CGFloat = 140
    private static let bottomBarWithChapters: CGFloat = 166

    private static func wordSlotHeight(fontSize: CGFloat) -> CGFloat {
        max(120, fontSize * 2.3)
    }

    @Test func clearHalfHeightIsTheRoomToTheNearerBar() {
        #expect(ReaderStageLayout.clearHalfHeight(centerY: 300, boundsHeight: 700, topBarHeight: 140, bottomBarHeight: 106) == 160)
        #expect(ReaderStageLayout.clearHalfHeight(centerY: 500, boundsHeight: 700, topBarHeight: 140, bottomBarHeight: 106) == 94)
    }

    @Test func clearHalfHeightIsZeroInsideABar() {
        #expect(ReaderStageLayout.clearHalfHeight(centerY: 100, boundsHeight: 700, topBarHeight: 140, bottomBarHeight: 106) == 0)
        #expect(ReaderStageLayout.clearHalfHeight(centerY: 650, boundsHeight: 700, topBarHeight: 140, bottomBarHeight: 106) == 0)
    }

    /// Safe-area heights and insets of the portrait phones in
    /// ReaderLayoutTests: Dynamic Island, home button, and zoomed home button.
    private static let portraitPhones: [(boundsHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat)] = [
        (759, 59, 34), (667, 0, 0), (568, 0, 0),
    ]

    @Test func contextShowsFullSizeOnPortraitPhonesAtEveryTextSize() throws {
        for phone in Self.portraitPhones {
            for size in Self.textSizes {
                let center = ReaderStageLayout.fixationCenterY(
                    boundsHeight: phone.boundsHeight, topInset: phone.topInset, bottomInset: phone.bottomInset,
                    contentHeight: Self.wordSlotHeight(fontSize: size),
                    topBarHeight: Self.topBar, bottomBarHeight: Self.bottomBarWithChapters
                )
                let room = ReaderStageLayout.clearHalfHeight(
                    centerY: center, boundsHeight: phone.boundsHeight,
                    topBarHeight: Self.topBar, bottomBarHeight: Self.bottomBarWithChapters
                )
                let metrics = try #require(ContextWords.metrics(wordFontSize: size, clearHalfHeight: room))
                #expect(abs(metrics.fontSize - ContextWords.preferredFontSize(wordFontSize: size)) < 0.001,
                        "phone \(phone.boundsHeight), size \(size)")
            }
        }
    }

    // MARK: - Rendering

    private enum ContextVariant {
        case absent, disabled, invisible, visible
    }

    /// One reader screen: its full size and safe-area insets.
    private struct Screen {
        let width: CGFloat
        let height: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat

        var stageHeight: CGFloat { height - topInset - bottomInset }

        static let phone = Screen(width: 393, height: 852, topInset: 59, bottomInset: 34)
        static let smallWindow = Screen(width: 700, height: 500, topInset: 32, bottomInset: 0)
    }

    private static let scale: CGFloat = 2

    /// The reader stage as ReaderView arranges it, with plain bars. Renders
    /// from its own defaults suite at the default Dynamic Type size, so no
    /// stored setting or device text size reaches the pixels.
    private struct Stage: View {
        let screen: Screen
        let engine: RSVPEngine
        let fontSize: CGFloat
        let variant: ContextVariant
        let defaults: UserDefaults

        var body: some View {
            ReaderStageLayout(topInset: screen.topInset, bottomInset: screen.bottomInset) {
                Color.gray
                    .frame(height: ContextWordsTests.topBar)
                    .readerStageRole(.topBar)

                WordView(word: engine.currentWord, fontSize: fontSize)

                switch variant {
                case .absent:
                    EmptyView()
                case .disabled:
                    ContextWordsView(engine: engine, fontSize: fontSize, isEnabled: false)
                        .readerStageRole(.fixationSurround)
                case .invisible:
                    ContextWordsView(engine: engine, fontSize: fontSize, isEnabled: true)
                        .opacity(0)
                        .readerStageRole(.fixationSurround)
                case .visible:
                    ContextWordsView(engine: engine, fontSize: fontSize, isEnabled: true)
                        .readerStageRole(.fixationSurround)
                }

                Color.gray
                    .frame(height: ContextWordsTests.bottomBarWithChapters)
                    .readerStageRole(.bottomBar)
            }
            .padding(.top, screen.topInset)
            .padding(.bottom, screen.bottomInset)
            .frame(width: screen.width, height: screen.height)
            .background(Color.black)
            .defaultAppStorage(defaults)
            .dynamicTypeSize(.large)
        }
    }

    /// RGBA rows of a rendered stage, top row first.
    private struct Bitmap: Equatable {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func row(_ y: Int) -> ArraySlice<UInt8> {
            bytes[(y * width * 4)..<((y + 1) * width * 4)]
        }
    }

    private static func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "ContextWordsTests.render"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private static func render(_ stage: Stage) throws -> Bitmap {
        let renderer = ImageRenderer(content: stage)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// Where the stage puts the word's center, measured from the top of the
    /// screen, and the context sizing for the room around it.
    private static func layout(_ screen: Screen, fontSize: CGFloat) -> (centerY: CGFloat, metrics: ContextWords.Metrics?) {
        let center = ReaderStageLayout.fixationCenterY(
            boundsHeight: screen.stageHeight, topInset: screen.topInset, bottomInset: screen.bottomInset,
            contentHeight: wordSlotHeight(fontSize: fontSize),
            topBarHeight: topBar, bottomBarHeight: bottomBarWithChapters
        )
        let room = ReaderStageLayout.clearHalfHeight(
            centerY: center, boundsHeight: screen.stageHeight,
            topBarHeight: topBar, bottomBarHeight: bottomBarWithChapters
        )
        return (screen.topInset + center, ContextWords.metrics(wordFontSize: fontSize, clearHalfHeight: room))
    }

    /// The pixel rows a slot covers: the slot above the word for `-1`,
    /// below it for `1`.
    private static func slotRows(centerY: CGFloat, metrics: ContextWords.Metrics, side: CGFloat) -> ClosedRange<Int> {
        let middle = centerY + side * metrics.offset
        let top = Int(((middle - metrics.slotHeight / 2) * scale).rounded(.down))
        let bottom = Int(((middle + metrics.slotHeight / 2) * scale).rounded(.up)) - 1
        return top...bottom
    }

    /// Rows that differ between two renders of the same screen.
    private static func changedRows(_ a: Bitmap, _ b: Bitmap) -> [Int] {
        (0..<a.height).filter { a.row($0) != b.row($0) }
    }

    private static let cases: [(words: [String], index: Int)] = [
        (["reading", "the", "information"], 1),
        (["of", "internationalization", "efforts,"], 1),
    ]

    @MainActor
    @Test func wordPixelsMatchWithContextAbsentDisabledOrInvisible() throws {
        let defaults = try Self.isolatedDefaults()
        for screen in [Screen.phone, .smallWindow] {
            for fontSize: CGFloat in [24, 40, 72] {
                for sample in Self.cases {
                    let engine = RSVPEngine(words: sample.words, currentIndex: sample.index)
                    func stage(_ variant: ContextVariant) -> Stage {
                        Stage(screen: screen, engine: engine, fontSize: fontSize, variant: variant, defaults: defaults)
                    }
                    // Early renders in a process can differ from later ones.
                    for _ in 0..<3 { _ = try Self.render(stage(.absent)) }
                    let absent = try Self.render(stage(.absent))
                    #expect(try Self.render(stage(.disabled)) == absent, "\(screen.width)pt, \(fontSize)pt, \(sample.words[sample.index])")
                    #expect(try Self.render(stage(.invisible)) == absent, "\(screen.width)pt, \(fontSize)pt, \(sample.words[sample.index])")
                }
            }
        }
    }

    @MainActor
    @Test func visibleContextOnlyChangesPixelsInsideItsSlots() throws {
        let defaults = try Self.isolatedDefaults()
        for screen in [Screen.phone, .smallWindow] {
            for fontSize: CGFloat in [24, 40, 72] {
                for sample in Self.cases {
                    let engine = RSVPEngine(words: sample.words, currentIndex: sample.index)
                    func stage(_ variant: ContextVariant) -> Stage {
                        Stage(screen: screen, engine: engine, fontSize: fontSize, variant: variant, defaults: defaults)
                    }
                    for _ in 0..<3 { _ = try Self.render(stage(.absent)) }
                    let absent = try Self.render(stage(.absent))
                    let visible = try Self.render(stage(.visible))
                    let changed = Self.changedRows(absent, visible)
                    let label = "\(screen.width)pt, \(fontSize)pt, \(sample.words[sample.index])"
                    let (centerY, metrics) = Self.layout(screen, fontSize: fontSize)
                    guard let metrics else {
                        #expect(changed.isEmpty, "\(label): context drew without room")
                        continue
                    }
                    let above = Self.slotRows(centerY: centerY, metrics: metrics, side: -1)
                    let below = Self.slotRows(centerY: centerY, metrics: metrics, side: 1)
                    #expect(changed.contains { above.contains($0) }, "\(label): no previous word")
                    #expect(changed.contains { below.contains($0) }, "\(label): no next word")
                    #expect(changed.allSatisfy { above.contains($0) || below.contains($0) }, "\(label): drew outside its slots")
                }
            }
        }
    }

    @MainActor
    @Test func firstWordShowsOnlyTheNextWord() throws {
        let defaults = try Self.isolatedDefaults()
        let engine = RSVPEngine(words: ["Call", "me", "Ishmael."], currentIndex: 0)
        func stage(_ variant: ContextVariant) -> Stage {
            Stage(screen: .phone, engine: engine, fontSize: 40, variant: variant, defaults: defaults)
        }
        for _ in 0..<3 { _ = try Self.render(stage(.absent)) }
        let absent = try Self.render(stage(.absent))
        let visible = try Self.render(stage(.visible))
        let changed = Self.changedRows(absent, visible)
        let (centerY, metrics) = Self.layout(.phone, fontSize: 40)
        let slot = try #require(metrics)
        let below = Self.slotRows(centerY: centerY, metrics: slot, side: 1)
        #expect(!changed.isEmpty)
        #expect(changed.allSatisfy { below.contains($0) })
    }

    @MainActor
    @Test func contextHidesDuringAChapterAnnouncement() throws {
        let defaults = try Self.isolatedDefaults()
        let engine = RSVPEngine(
            words: ["reading", "the", "information"], currentIndex: 1,
            chapters: [Chapter(title: "Chapter Two", wordIndex: 1)]
        )
        engine.play()
        defer { engine.pause() }
        #expect(engine.chapterAnnouncement != nil)
        func stage(_ variant: ContextVariant) -> Stage {
            Stage(screen: .phone, engine: engine, fontSize: 40, variant: variant, defaults: defaults)
        }
        for _ in 0..<3 { _ = try Self.render(stage(.absent)) }
        let absent = try Self.render(stage(.absent))
        let visible = try Self.render(stage(.visible))
        #expect(visible == absent)
    }
}
