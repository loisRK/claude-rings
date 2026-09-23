import AppKit
import ClaudeRingsCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AccountStore()
    private var sessions = SessionWatcher()
    private var model: UsageViewModel?
    private var menuBar: MenuBarController?
    private var sessionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 토큰 자동 갱신은 Keychain 쓰기가 실제로 되는 환경에서만 켠다. GUI 앱에는 제어
        // 터미널이 없어 `security`가 값을 stdin에서 받는지 미리 알 수 없으므로, 실제
        // 자격증명을 건드리기 전에 일회용 항목으로 한 번 확인한다.
        let probe = KeychainCredentialWriter()
        let transport = probe.resolveTransport()
        let writer = transport.map { probe.using($0) }
        Logger(subsystem: "com.loisrk.ClaudeRings", category: "auth")
            .notice("토큰 자동 갱신: \(transport == nil ? "꺼짐" : "켜짐", privacy: .public) (전달 방식: \(transport.map { String(describing: $0) } ?? "없음", privacy: .public))")
        let model = UsageViewModel(
            config: store.load(),
            registry: .claudeOnly(
                refresher: writer == nil ? nil : OAuthTokenRefresher(),
                writer: writer))
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
