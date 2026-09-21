import AppKit
import ClaudeRingsCore

/// 팝오버의 `ColorPicker`가 여는 시스템 색상 패널(`NSColorPanel`)이 실제로 사용자
/// 눈에 보이도록 미리 손봐 둔다.
///
/// 실제 앱을 계측해서 확인한 문제(클릭이 무시되는 게 아니었다. 패널은 매번 정상으로
/// 열리고 있었다):
/// 1. `NSColorPanel`은 자기 위치를 `UserDefaults`의 `"NSWindow Frame NSColorPanel"`에
///    저장해 두고 항상 그 자리에서 열린다. 한 번 화면 구석이나 다른 모니터에 놓이면
///    그다음부터는 계속 거기서 열려서, 메뉴바 아래 팝오버를 보고 있는 사용자에게는
///    "눌러도 아무 일이 없다"로 보인다.
/// 2. `NSPanel`은 기본값이 `hidesOnDeactivate == true`다. 이 앱은 `.accessory`라
///    활성 상태가 오래 유지되지 않아서, 패널이 떴다가 몇 초 만에 스스로 사라진다.
/// 3. 팝오버는 `.statusBar` 레벨(25)에 뜨는데 색상 패널은 기본이 `.floating`(3)이라,
///    자리가 겹치면 팝오버 뒤로 가려진다.
///
/// 그래서 팝오버를 열 때마다 공유 패널을 미리 만들어(만들기만 해서는 보이지 않는다)
/// 위 세 가지를 고쳐 둔다. `ColorPicker`가 실제로 패널을 여는 시점에는 이미 제자리·
/// 올바른 설정이므로, 패널이 열리는 순간을 따로 감시할 필요가 없다.
@MainActor
final class ColorPanelPresenter {
    /// 팝오버와 패널 사이 여백.
    private let gap: CGFloat = 12

    /// 팝오버가 열린 직후에 호출한다. 패널을 띄우지는 않는다.
    func prepare(anchoredTo popoverWindow: NSWindow?) {
        let panel = NSColorPanel.shared
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        guard let popoverWindow, let screen = popoverWindow.screen ?? NSScreen.main else { return }
        panel.setFrameOrigin(
            PanelPlacement.besidePopover(
                panelSize: panel.frame.size,
                popover: popoverWindow.frame,
                screen: screen.visibleFrame,
                gap: gap))
    }

    /// 팝오버가 닫히면 색상 패널도 같이 치운다. `hidesOnDeactivate`를 껐기 때문에
    /// 그냥 두면 팝오버가 사라진 뒤에도 패널만 화면에 남는다.
    func dismiss() {
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.orderOut(nil)
    }
}
