import AppKit
import ClaudeRingsCore
import SwiftUI

struct RingsActions {
    let refresh: @MainActor () -> Void
    let openConfig: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

/// 계정 수와 무관하게 `NSStatusItem` 하나를 관리하고, 클릭하면 팝오버를 연다.
///
/// 메뉴바 콘텐츠는 `NSHostingView`를 `statusItem.button`에 실시간으로 얹어서 보여준다
/// (검증 과정에서, 정적 이미지로 구운 뒤 넣는 방식은 시스템 다크/라이트 모드를 따라가지
/// 못한다는 걸 확인해 라이브 호스팅으로 유지한다). `UsageViewModel`·`ThemeStore` 모두
/// `@Observable`이라 값이 바뀌면 이 서브뷰가 자동으로 다시 그려지므로 별도 타이머로
/// 다시 그릴 필요가 없다.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(model: UsageViewModel, theme: ThemeStore, loginItem: LoginItemModel, actions: RingsActions) {
        super.init()

        if let button = statusItem.button {
            let hosting = NSHostingView(rootView: MenuBarContentView(model: model, theme: theme))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            // .variableLength는 버튼 안 커스텀 SwiftUI 서브뷰의 크기를 자동으로 반영하지
            // 않으므로, 콘텐츠의 적정 너비를 계산해 아이템 길이로 직접 설정한다. 계정
            // 목록은 시작 시 1회만 로드되어 실행 중 바뀌지 않으므로 한 번만 계산하면 된다.
            statusItem.length = hosting.fittingSize.width
        }

        let popoverController = NSHostingController(
            rootView: PopoverContentView(model: model, theme: theme, loginItem: loginItem, actions: actions))
        // NSHostingController는 기본적으로 preferredContentSize를 SwiftUI 콘텐츠에 맞춰
        // 갱신하지 않는다. 이 옵션을 켜야 NSPopover가 실제 콘텐츠 높이대로 창을 잡고,
        // 계정이 늘거나 조회 일시 제한 문구가 붙어 콘텐츠가 커져도 다시 반영된다
        // (안 켜두면 팝오버가 예전/기본 크기로 고정돼 위쪽 내용이 잘려 보인다).
        popoverController.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.contentViewController = popoverController

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
