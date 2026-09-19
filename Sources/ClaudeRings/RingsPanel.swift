import AppKit
import SwiftUI

struct RingsActions {
    let refresh: @MainActor () -> Void
    let resetPosition: @MainActor () -> Void
    let openConfig: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

/// 창 자체는 투명하고 SwiftUI 콘텐츠만 보이는, 모든 Space의 항상 위 패널.
/// 콘텐츠 크기가 바뀌면 오른쪽 위 모서리를 기준으로 크기를 맞춘다.
@MainActor
final class RingsPanel: NSPanel {
    private static let anchorKey = "panelTopRight"
    private static let margin = CGSize(width: 16, height: 12)

    init(model: UsageViewModel, actions: RingsActions) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true

        let root = RingsView(model: model, actions: actions) { [weak self] size in
            self?.fit(to: size)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        contentView = hosting

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
        fit(to: frame.size)
    }

    private func fit(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let topRight = savedTopRight ?? defaultTopRight
        setFrame(
            NSRect(x: topRight.x - size.width, y: topRight.y - size.height, width: size.width, height: size.height),
            display: true)
    }

    private var savedTopRight: CGPoint? {
        UserDefaults.standard.string(forKey: Self.anchorKey).map(NSPointFromString)
    }

    private var defaultTopRight: CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: visible.maxX - Self.margin.width, y: visible.maxY - Self.margin.height)
    }

    @objc private func didMove(_ notification: Notification) {
        UserDefaults.standard.set(
            NSStringFromPoint(NSPoint(x: frame.maxX, y: frame.maxY)), forKey: Self.anchorKey)
    }
}
