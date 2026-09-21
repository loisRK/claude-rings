import Testing

@testable import ClaudeRingsCore

struct ThemeTests {
    @Test func hexRoundTripsWithAndWithoutHash() {
        #expect(RGBAColor(hex: "#FF0000")?.hexString == "#FF0000")
        #expect(RGBAColor(hex: "00FF00")?.hexString == "#00FF00")
        #expect(RGBAColor(hex: "#0000FF")?.hexString == "#0000FF")
    }

    @Test func hexWithAlphaParsesButHexStringDropsAlpha() {
        let color = RGBAColor(hex: "#FF000080")
        #expect(color != nil)
        #expect(color?.hexString == "#FF0000")
    }

    @Test func invalidHexReturnsNil() {
        #expect(RGBAColor(hex: "") == nil)
        #expect(RGBAColor(hex: "#ZZZZZZ") == nil)
        #expect(RGBAColor(hex: "#FFF") == nil)
        #expect(RGBAColor(hex: "#FF00000000") == nil)
    }

    @Test(arguments: [
        (100, RingLevel.good), (50, .good),
        (49, .warning), (20, .warning),
        (19, .critical), (0, .critical),
    ])
    func levelColorPicksExpectedLevel(remaining: Int, expected: RingLevel) {
        let theme = LevelColors.default
        let expectedColor: RGBAColor? = switch expected {
        case .good: theme.good
        case .warning: theme.warning
        case .critical: theme.critical
        case .unavailable: nil
        }
        #expect(theme.color(for: remaining) == expectedColor)
    }

    @Test func levelColorIsNilWhenRemainingIsMissing() {
        #expect(LevelColors.default.color(for: nil) == nil)
    }
}
