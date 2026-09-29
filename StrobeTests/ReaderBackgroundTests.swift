import Testing
@testable import Strobe

struct ReaderBackgroundTests {

    @Test func resolvesTheSettingToABackground() {
        #expect(ReaderBackground.resolve(trueBlackEnabled: false) == .standard)
        #expect(ReaderBackground.resolve(trueBlackEnabled: true) == .trueBlack)
    }
}
