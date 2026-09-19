import AppKit
import ClaudeRingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AccountStore()
    private let standalone = CommandLine.arguments.contains("--standalone")
    private var sessions = SessionWatcher()
    private var model: UsageViewModel?
    private var panel: RingsPanel?
    private var sessionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageViewModel(
            config: store.load(),
            poller: AccountPoller(tokens: KeychainTokenProvider(), fetcher: UsageClient()))
        let store = store
        let panel = RingsPanel(
            model: model,
            actions: RingsActions(
                refresh: { [weak model] in model?.refreshAll() },
                resetPosition: { [weak self] in self?.panel?.resetPosition() },
                openConfig: { NSWorkspace.shared.open(store.fileURL) },
                quit: { NSApp.terminate(nil) }))
        self.model = model
        self.panel = panel

        panel.orderFrontRegardless()
        model.start()
        checkSessions()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSessions() }
        }
    }

    private func checkSessions() {
        let snapshot = sessions.tick()
        model?.activeConfigDirs = snapshot.activeConfigDirs
        if snapshot.shouldQuit && !standalone {
            NSApp.terminate(nil)
        }
    }
}
