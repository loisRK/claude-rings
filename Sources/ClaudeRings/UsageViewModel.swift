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
    // 계정별 캐시 상태(마지막 성공 사용량·시각, 조회 일시 제한 해제 시각). 디스크의
    // UsageCache와 항상 동기화해 재시작 후에도 스케줄링에 이어 쓸 수 있게 한다(I2).
    @ObservationIgnored private var cache: [String: UsageCache.AccountState]
    // refreshAll()이 과도하게 조회하지 않도록(I3) 계정별 마지막 조회 시작 시각을 기록한다.
    @ObservationIgnored private var lastPollStartedAt: [String: Date] = [:]
    // Backoff는 모델에 두어 refreshAll()로 폴링 루프를 다시 시작해도 초기화되지 않게 한다(I3).
    @ObservationIgnored private var backoffs: [String: Backoff] = [:]

    init(config: AppConfig, poller: AccountPoller, now: Date = .now) {
        accounts = config.accounts
        let interval = TimeInterval(max(30, config.pollIntervalSeconds))
        let loaded = UsageCache.load(now: now)
        cache = loaded
        statuses = Dictionary(config.accounts.map { account in
            let state = loaded[account.name]
            let status = PollSchedule.initialStatus(
                cachedUsage: state?.usage, lastSuccessAt: state?.lastSuccessAt, now: now, interval: interval)
            return (account.name, status)
        }, uniquingKeysWith: { first, _ in first })
        blockedUntil = loaded.compactMapValues { state in
            state.blockedUntil.flatMap { $0 > now ? $0 : nil }
        }
        self.poller = poller
        baseInterval = interval
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
        let now = Date.now
        for account in accounts {
            startLoop(for: account, initialDelay: initialDelay(for: account, now: now))
        }
    }

    /// 수동 새로고침. 조회 일시 제한 중이거나 최근에 조회한 계정은 건너뛴다(I3).
    func refreshAll() {
        let now = Date.now
        for account in accounts {
            guard PollSchedule.shouldRefresh(
                now: now, blockedUntil: blockedUntil[account.name], lastPollStartedAt: lastPollStartedAt[account.name])
            else { continue }
            startLoop(for: account)
        }
    }

    private func initialDelay(for account: Account, now: Date) -> TimeInterval {
        let state = cache[account.name]
        return PollSchedule.initialDelay(
            now: now, lastSuccessAt: state?.lastSuccessAt, blockedUntil: state?.blockedUntil, interval: baseInterval)
    }

    private func startLoop(for account: Account, initialDelay: TimeInterval = 0) {
        tasks[account.name]?.cancel()
        tasks[account.name] = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                }
                guard let self else { return }
                delay = await self.pollOnce(account)
            }
        }
    }

    private func pollOnce(_ account: Account) async -> TimeInterval {
        lastPollStartedAt[account.name] = .now
        let previous = status(for: account)
        let outcome = await poller.poll(account, previous: previous)
        guard !Task.isCancelled else { return baseInterval }
        statuses[account.name] = outcome.status

        var backoff = backoffs[account.name] ?? Backoff(base: baseInterval)
        if outcome.transientFailure {
            backoff.recordFailure()
        } else {
            backoff.recordSuccess()
        }
        backoffs[account.name] = backoff
        let delay = PollSchedule.nextDelay(backoff: backoff.interval, retryAfter: outcome.retryAfter)

        var state = cache[account.name] ?? UsageCache.AccountState()
        if case .ok(let usage) = outcome.status {
            state.usage = usage
            state.lastSuccessAt = .now
        }
        if outcome.retryAfter != nil {
            let until = Date.now.addingTimeInterval(delay)
            blockedUntil[account.name] = until
            state.blockedUntil = until
        } else {
            blockedUntil.removeValue(forKey: account.name)
            state.blockedUntil = nil
        }
        cache[account.name] = state
        UsageCache.save(cache)

        return delay
    }
}
