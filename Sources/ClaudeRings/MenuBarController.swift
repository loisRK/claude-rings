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
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let loginItem: LoginItemModel
    /// 팝오버를 열기 직전까지 맨 앞에 있던 앱. 팝오버가 닫히면 이 앱으로 포커스를
    /// 돌려준다(우리 앱은 accessory라 Dock 아이콘이 없고, 사용자가 원래 보던 창을
    /// 방해하지 않아야 하기 때문).
    private var previousApp: NSRunningApplication?

    init(model: UsageViewModel, theme: ThemeStore, loginItem: LoginItemModel, actions: RingsActions) {
        self.loginItem = loginItem
        super.init()

        if let button = statusItem.button {
            let hosting = NSHostingView(
                rootView: MenuBarContentView(model: model, theme: theme, onWidthChange: { [weak self] width in
                    self?.updateStatusItemWidth(width)
                }))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            // .variableLength는 버튼 안 커스텀 SwiftUI 서브뷰의 크기를 자동으로 반영하지
            // 않으므로 초기값을 직접 잡아 둔다. 실제 지속적인 갱신은 onWidthChange로
            // 한다 — 캐시 없이 시작하면 "—"만 보이다가 숫자가 채워지거나, 조회 일시
            // 제한으로 시계+남은 시간 문구가 붙는 등 텍스트 폭 자체가 실행 중 바뀌기
            // 때문에(검증 중 발견) 한 번만 재는 것으로는 잘릴 수 있다.
            statusItem.length = hosting.fittingSize.width
        }

        let popoverController = NSHostingController(
            rootView: PopoverContentView(model: model, theme: theme, loginItem: loginItem, actions: actions))
        // NSHostingController는 기본적으로 preferredContentSize를 SwiftUI 콘텐츠에 맞춰
        // 갱신하지 않는다. 이 옵션을 켜야 NSPopover가 실제 콘텐츠 높이대로 창을 잡고,
        // 계정이 늘거나 조회 일시 제한 문구가 붙어 콘텐츠가 커져도 다시 반영된다
        // (안 켜두면 팝오버가 예전/기본 크기로 고정돼 위쪽 내용이 잘려 보인다).
        popoverController.sizingOptions = [.preferredContentSize]
        // .transient면 NSColorPanel(색상 설정의 ColorPicker가 여는 창)이 키 윈도우가
        // 되는 순간 팝오버가 바깥 클릭으로 오인해 닫혀 버려 색상 편집을 쓸 수 없다.
        // .semitransient는 그런 보조 창이 떠 있는 동안은 안 닫히면서도, 바깥을 클릭하면
        // 여전히 닫힌다.
        popover.behavior = .semitransient
        popover.contentViewController = popoverController
        popover.delegate = self

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    private func updateStatusItemWidth(_ width: CGFloat) {
        guard width > 0, abs(statusItem.length - width) > 0.5 else { return }
        statusItem.length = width
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
        // 시스템 설정에서 로그인 항목을 직접 바꿨을 수 있으니 열 때마다 최신 상태로 갱신한다.
        loginItem.refresh()

        // 앱이 .accessory(LSUIElement)라 활성화된 적이 없으면 팝오버 창이 key가 되지
        // 않아 ColorPicker를 눌러도 NSColorPanel이 열리지 않는다(검증 중 재현·확인).
        // 활성화해야 팝오버가 실제로 key window가 된다. Dock 아이콘은 activationPolicy가
        // 그대로 .accessory라 여전히 뜨지 않는다.
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// 팝오버가 닫히면(바깥 클릭, 다시 클릭, ESC 등 어떤 이유든) 원래 맨 앞에 있던
    /// 앱으로 포커스를 돌려준다. `NSApp.activate()`로 우리 앱을 활성화한 뒤라 그냥
    /// 두면 사용자가 보던 창이 뒤로 밀린 채 남기 때문이다.
    func popoverDidClose(_ notification: Notification) {
        previousApp?.activate(options: [])
        previousApp = nil
    }
}
