import ClaudeRingsCore
import Foundation
import Observation

@MainActor
@Observable
final class UsageViewModel {
    let accounts: [Account]
    private(set) var statuses: [String: AccountStatus]
    /// 429 Retry-After로 사용량 조회 API가 일시 차단된 계정의 해제 시각.
    private(set) var blockedUntil: [String: Date] = [:]
    var activeConfigDirs: Set<String> = []

    @ObservationIgnored private let poller: AccountPoller
    @ObservationIgnored private let baseInterval: TimeInterval
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    // 마지막 성공 사용량 캐시(계정별). 콜드 스타트 직후 첫 조회가 실패해도 화면이
    // -1 / -1로 비지 않도록 초기 상태를 채우는 데 쓴다.
    @ObservationIgnored private var cachedUsages: [String: Usage]

    init(config: AppConfig, poller: AccountPoller) {
        accounts = config.accounts
        let cached = UsageCache.load()
        statuses = Dictionary(config.accounts.map { account in
            (account.name, cached[account.name].map(AccountStatus.stale) ?? .loading)
        }, uniquingKeysWith: { first, _ in first })
        cachedUsages = cached
        self.poller = poller
        baseInterval = TimeInterval(max(30, config.pollIntervalSeconds))
    }

    func status(for account: Account) -> AccountStatus {
        statuses[account.name] ?? .loading
    }

    func blockedUntil(for account: Account) -> Date? {
        blockedUntil[account.name]
    }

    func isActive(_ account: Account) -> Bool {
        activeConfigDirs.contains(KeychainService.normalize(account.configDir))
    }

    func start() {
        for account in accounts {
            startLoop(for: account)
        }
    }

    func refreshAll() {
        start()
    }

    private func startLoop(for account: Account) {
        tasks[account.name]?.cancel()
        let poller = poller
        let base = baseInterval
        tasks[account.name] = Task { [weak self] in
            var backoff = Backoff(base: base)
            while !Task.isCancelled {
                let previous = self?.status(for: account) ?? .loading
                let outcome = await poller.poll(account, previous: previous)
                guard !Task.isCancelled, let self else { return }
                self.statuses[account.name] = outcome.status
                if case .ok(let usage) = outcome.status {
                    self.cachedUsages[account.name] = usage
                    UsageCache.save(self.cachedUsages)
                }
                if let retryAfter = outcome.retryAfter {
                    self.blockedUntil[account.name] = Date.now.addingTimeInterval(min(retryAfter, 7200))
                } else {
                    self.blockedUntil.removeValue(forKey: account.name)
                }
                if outcome.transientFailure {
                    backoff.recordFailure()
                } else {
                    backoff.recordSuccess()
                }
                try? await Task.sleep(
                    for: .seconds(PollSchedule.nextDelay(backoff: backoff.interval, retryAfter: outcome.retryAfter)))
            }
        }
    }
}
