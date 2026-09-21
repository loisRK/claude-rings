import AppKit
import ClaudeRingsCore
import SwiftUI

struct RingsActions {
    let refresh: @MainActor () -> Void
    let openConfig: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

/// 계정 수와 무관하게 `NSStatusItem` 하나를 관리하고, 클릭하면 팝오버를 연다.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(model: UsageViewModel, loginItem: LoginItemModel, actions: RingsActions) {
        super.init()

        installMenuBarContent(model: model)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(model: model, loginItem: loginItem, actions: actions))

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    private func installMenuBarContent(model: UsageViewModel) {
        guard let button = statusItem.button else { return }
        let hosting = NSHostingView(rootView: MenuBarContentView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        // .variableLength는 버튼 안의 커스텀 SwiftUI 서브뷰 크기를 자동으로 반영하지
        // 않으므로, 콘텐츠의 적정 너비를 계산해 아이템 길이로 직접 설정한다. 계정 목록은
        // 시작 시 1회만 로드되어 실행 중 바뀌지 않으므로 한 번만 계산하면 된다.
        button.layoutSubtreeIfNeeded()
        var width = hosting.fittingSize.width
        if width <= 0 {
            width = CGFloat(64 * max(model.accounts.count, 1))
        }
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
