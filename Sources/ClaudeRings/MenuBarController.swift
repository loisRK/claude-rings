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
    /// `ColorPicker`가 여는 시스템 색상 패널이 팝오버 옆에 보이게 만들어 준다.
    private let colorPanel = ColorPanelPresenter()
    /// 팝오버를 열기 직전까지 맨 앞에 있던 앱. 팝오버가 닫히면 이 앱으로 포커스를
    /// 돌려준다(우리 앱은 accessory라 Dock 아이콘이 없고, 사용자가 원래 보던 창을
    /// 방해하지 않아야 하기 때문).
    private var previousApp: NSRunningApplication?
    /// 팝오버가 열려 있는 동안에만 살아 있는 바깥 클릭·ESC 감시자들.
    private var dismissMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

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
        // .transient면 NSColorPanel(색상 설정의 ColorPicker가 여는 창)이 뜨는 순간
        // 팝오버가 바깥 클릭으로 오인해 닫혀 버려 색상 편집을 쓸 수 없다. 반대로
        // .semitransient는 "위치 기준 뷰가 들어 있는 창" 안의 조작에만 반응하므로,
        // 다른 앱을 클릭해도 팝오버가 안 닫혀 배터리 등 다른 메뉴바 항목과 다르게
        // 동작한다(사용자 보고). 그래서 자동 닫기를 아예 끄고(.applicationDefined)
        // `startDismissWatchers()`에서 직접 판단한다.
        popover.behavior = .applicationDefined
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

        // 앱이 .accessory(LSUIElement)라, 활성화하지 않으면 팝오버 창이 key window가
        // 되지 않아 키보드 입력이나 색상 패널 같은 보조 창을 제대로 쓸 수 없다.
        // 활성화하면 팝오버가 key가 되는 것을 계측으로 확인했다. Dock 아이콘은
        // activationPolicy가 그대로 .accessory라 여전히 뜨지 않는다.
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.makeKey()
        colorPanel.prepare(anchoredTo: popoverWindow)
        startDismissWatchers()
    }

    /// `.applicationDefined`라 NSPopover가 스스로 닫히는 일이 없다. 일반적인 메뉴바
    /// 팝오버처럼 보이도록, 열려 있는 동안만 아래 경우를 직접 지켜보다가 닫는다.
    ///
    /// - 다른 앱·데스크톱·메뉴바 클릭(전역 마우스 모니터). 전역 모니터에는 우리 앱으로
    ///   가는 이벤트가 오지 않으므로, 여기 걸렸다면 그 자체가 "바깥 클릭"이다.
    /// - 우리 앱 안이지만 팝오버·상태 항목·색상 패널이 아닌 창의 클릭(로컬 모니터).
    /// - ESC.
    /// - 앱 비활성화, 그리고 다른 앱의 활성화. 마우스를 쓰지 않은 앱 전환(Cmd+Tab 등)은
    ///   위 마우스 모니터에 안 잡힌다.
    ///
    /// 색상 패널은 우리 앱 소유라 그 위의 클릭은 전역 모니터에 잡히지 않고, 로컬
    /// 모니터에서는 예외로 두므로 색을 고르는 동안 팝오버가 닫히지 않는다.
    private func startDismissWatchers() {
        stopDismissWatchers()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }) {
            dismissMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, !self.keepsPopoverOpen(event.window) { self.closePopover() }
            }
            return event
        }) {
            dismissMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // 53 = ESC. 팝오버가 닫히는 대신 텍스트 필드 등으로 새어 나가지 않도록 삼킨다.
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePopover() }
            return nil
        }) {
            dismissMonitors.append(monitor)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }

        // `didResignActive`만으로는 부족하다. 이 앱은 .accessory라 `NSApp.activate()`를
        // 해도 시스템이 보는 "맨 앞 앱"은 그대로인 경우가 있고(계측으로 확인), 그때는
        // 다른 앱으로 넘어가도 비활성화 알림이 오지 않는다. 그래서 "다른 앱이 활성화됐다"를
        // 워크스페이스 쪽에서도 같이 본다 — Cmd+Tab, Spotlight, Mission Control처럼
        // 마우스를 안 쓰는 전환까지 잡힌다.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.closePopover() }
        }
    }

    private func stopDismissWatchers() {
        for monitor in dismissMonitors { NSEvent.removeMonitor(monitor) }
        dismissMonitors.removeAll()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// 이 창 위의 클릭은 "바깥 클릭"으로 보지 않는다. 상태 항목을 넣어 두는 이유:
    /// 상태 항목을 다시 누르면 `togglePopover()`가 닫아야 하는데, 모니터가 먼저 닫아
    /// 버리면 뒤이어 실행되는 액션이 `isShown == false`를 보고 곧바로 다시 연다.
    private func keepsPopoverOpen(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if window === popover.contentViewController?.view.window { return true }
        if window === statusItem.button?.window { return true }
        if NSColorPanel.sharedColorPanelExists, window === NSColorPanel.shared { return true }
        return false
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 팝오버가 닫히면(바깥 클릭, 다시 클릭, ESC 등 어떤 이유든) 원래 맨 앞에 있던
    /// 앱으로 포커스를 돌려준다. `NSApp.activate()`로 우리 앱을 활성화한 뒤라 그냥
    /// 두면 사용자가 보던 창이 뒤로 밀린 채 남기 때문이다.
    ///
    /// 단, 팝오버가 열려 있는 동안 사용자가 Cmd+Tab 등으로 이미 다른 앱(AppB)으로
    /// 포커스를 옮겼다면(그 전환 자체가 팝오버를 닫히게 함) 여기서 원래 앱(AppA)을
    /// 강제로 앞에 세우면 사용자의 그 전환을 덮어써 버린다. 그래서 "지금도 여전히
    /// 우리 앱이 맨 앞인지"를 닫히는 시점에 다시 확인해서, 우리가 맨 앞일 때만
    /// 되돌린다 — 우리가 아니라면 사용자가 이미 다른 곳으로 옮긴 것이므로 그대로 둔다.
    func popoverDidClose(_ notification: Notification) {
        defer { previousApp = nil }
        stopDismissWatchers()
        colorPanel.dismiss()
        guard let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        else { return }
        previousApp.activate(options: [])
    }
}
