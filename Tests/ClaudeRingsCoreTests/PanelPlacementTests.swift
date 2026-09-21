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

    @Test("패널이 팝오버보다 훨씬 높아도 화면 위아래를 벗어나지 않는다")
    func doesNotOverflowScreenWithTallPanel() {
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 900),
            popover: CGRect(x: 900, y: 500, width: 296, height: 406),
            screen: screen,
            gap: 12)
        #expect(origin.y + 900 <= screen.maxY)
        #expect(origin.y >= screen.minY)
    }

    // MARK: - 세로 배치 경계

    /// 상태 항목 팝오버의 실제 형상: 팝오버 위쪽이 `visibleFrame` 위 끝(메뉴바 바로 아래)에 닿는다.
    @Test("팝오버 위쪽이 화면 위 끝에 딱 닿으면 패널 위쪽도 화면 위 끝에 맞는다")
    func alignsPanelTopToScreenTopWhenPopoverIsFlushWithTop() {
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: CGRect(x: 900, y: screen.maxY - 406, width: 296, height: 406),
            screen: screen,
            gap: 12)
        #expect(origin.y == screen.maxY - 397)
        #expect(origin.y + 397 == screen.maxY)
    }

    /// 팝오버는 메뉴바 영역까지 걸칠 수 있어서 `maxY`가 `visibleFrame.maxY`를 넘길 수 있다.
    /// 그대로 위쪽을 맞추면 패널이 화면 위로 삐져나가므로 위쪽 한계로 눌러야 한다.
    @Test("팝오버 위쪽이 화면 위 끝보다 높으면 패널을 화면 안으로 내린다")
    func clampsDownWhenPopoverTopIsAboveScreenTop() {
        let popover = CGRect(x: 900, y: 580, width: 296, height: 406)
        #expect(popover.maxY > screen.maxY)  // 전제: 순진하게 맞추면 화면 위로 넘어간다
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: popover,
            screen: screen,
            gap: 12)
        #expect(origin.y == screen.maxY - 397)
        #expect(origin.y + 397 <= screen.maxY)
    }

    /// 팝오버가 화면 아래쪽에 있어서 위쪽을 맞추면 패널이 화면 아래로 빠지는 경우.
    @Test("팝오버가 화면 아래쪽에 있으면 패널을 화면 아래 끝까지만 내린다")
    func clampsUpWhenNaiveOriginFallsBelowScreen() {
        let secondary = CGRect(x: -212, y: 982, width: 1920, height: 1080)
        let popover = CGRect(x: 906, y: secondary.minY, width: 296, height: 120)
        #expect(popover.maxY - 397 < secondary.minY)  // 전제: 순진하게 맞추면 화면 아래로 빠진다
        let origin = PanelPlacement.besidePopover(
            panelSize: CGSize(width: 250, height: 397),
            popover: popover,
            screen: secondary,
            gap: 12)
        #expect(origin.y == secondary.minY)
    }

    /// 패널이 화면보다 높으면 위·아래 한계가 뒤집힌다(`upper < lower`). 이때 NaN이나
    /// 화면 밖 좌표가 아니라 아래쪽 한계를 돌려줘야 한다.
    @Test("패널이 화면보다 높으면 화면 아래 끝에 붙인다")
    func fallsBackToLowerBoundWhenPanelIsTallerThanScreen() {
        let secondary = CGRect(x: -212, y: 982, width: 1920, height: 1080)
        let tall = CGSize(width: 250, height: 1200)
        #expect(tall.height > secondary.height)  // 전제: 한계가 뒤집힌다
        let origin = PanelPlacement.besidePopover(
            panelSize: tall,
            popover: CGRect(x: 906, y: 1630, width: 296, height: 406),
            screen: secondary,
            gap: 12)
        #expect(origin.y.isFinite)
        #expect(origin.y == secondary.minY)
    }
}
