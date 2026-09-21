import AppKit
import ClaudeRingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AccountStore()
    private var sessions = SessionWatcher()
    private var model: UsageViewModel?
    private var menuBar: MenuBarController?
    private var sessionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageViewModel(
            config: store.load(),
            registry: .claudeOnly())
        let store = store
        let loginItem = LoginItemModel()
        let theme = ThemeStore()
        let menuBar = MenuBarController(
            model: model,
            theme: theme,
            loginItem: loginItem,
            actions: RingsActions(
                refresh: { [weak model] in model?.refreshAll() },
                openConfig: { NSWorkspace.shared.open(store.fileURL) },
                quit: { NSApp.terminate(nil) }))
        self.model = model
        self.menuBar = menuBar

        model.start()
        checkSessions()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSessions() }
        }
    }

    /// 실행 중인 계정 표시(●)만 갱신한다. 메뉴바 앱은 세션이 모두 끝나도 종료하지 않는다.
    private func checkSessions() {
        let snapshot = sessions.tick()
        model?.activeConfigDirs = snapshot.activeConfigDirs
    }
}
