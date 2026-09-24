import Testing
@testable import Strobe

struct ReaderBackgroundTests {

    @Test func resolvesTheSettingToABackground() {
        #expect(ReaderBackground.resolve(trueBlackEnabled: false) == .standard)
        #expect(ReaderBackground.resolve(trueBlackEnabled: true) == .trueBlack)
    }

    @Test func trueBlackIsOnByDefault() {
        #expect(ReaderSettings.Defaults.trueBlackBackgroundEnabled == true)
        #expect(ReaderBackground.resolve(
            trueBlackEnabled: ReaderSettings.Defaults.trueBlackBackgroundEnabled
        ) == .trueBlack)
    }
}
