import CoreGraphics
import Testing

@testable import ClaudeRingsCore

@Suite("PanelPlacement")
struct PanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)

    @Test("팝오버 왼쪽에 자리가 있으면 왼쪽에 붙인다")
    func placesLeftWhenThereIsRoom() {
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: CGRect(x: 900, y: 500, width: 296, height: 406),
            screen: screen,
            gap: 12)
        #expect(origin.x == CGFloat(900 - 12 - 250))
        // 세로는 팝오버 위쪽에 맞춘다(팝오버는 메뉴바 아래에서 아래로 자란다).
        #expect(origin.y == CGFloat(906 - 397))
    }

    @Test("왼쪽에 자리가 없으면 오른쪽에 붙인다")
    func placesRightWhenLeftIsTooNarrow() {
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: CGRect(x: 40, y: 500, width: 296, height: 406),
            screen: screen,
            gap: 12)
        #expect(origin.x == CGFloat(40 + 296 + 12))
    }

    @Test("어느 쪽에도 자리가 없으면 화면 안으로 밀어 넣는다")
    func clampsIntoScreenWhenNeitherSideFits() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 400)
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: CGRect(x: 60, y: 0, width: 296, height: 400),
            screen: narrow,
            gap: 12)
        #expect(origin.x >= narrow.minX)
        #expect(origin.x + 250 <= narrow.maxX)
        #expect(origin.y >= narrow.minY)
        #expect(origin.y + 397 <= narrow.maxY)
    }

    @Test("화면 원점이 음수인 보조 모니터에서도 그 화면 안에 놓는다")
    func staysOnSecondaryScreenWithNegativeOrigin() {
        let secondary = CGRect(x: -212, y: 982, width: 1920, height: 1080)
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: CGRect(x: 906, y: 1630, width: 296, height: 406),
            screen: secondary,
            gap: 12)
        #expect(origin.x >= secondary.minX)
        #expect(origin.x + 250 <= secondary.maxX)
        #expect(origin.y >= secondary.minY)
        #expect(origin.y + 397 <= secondary.maxY)
        #expect(origin.x == CGFloat(906 - 12 - 250))
    }

    @Test("팝오버가 화면 위쪽 끝에 붙어 있어도 패널이 화면 위로 넘어가지 않는다")
    func doesNotOverflowScreenTop() {
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 900),
            popover: CGRect(x: 900, y: 500, width: 296, height: 406),
            screen: screen,
            gap: 12)
        #expect(origin.y + 900 <= screen.maxY)
        #expect(origin.y >= screen.minY)
    }
}
