import Foundation
import Testing
@testable import ClaudeRingsCore

final class StubTokens: TokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<Credential, TokenError>]
    private(set) var calls = 0

    init(_ queue: [Result<Credential, TokenError>]) { self.queue = queue }

    func credential(for account: Account) throws(TokenError) -> Credential {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        let next = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try next.get()
    }
}

final class StubFetcher: UsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [FetchResult]
    private(set) var tokensSeen: [String] = []

    init(_ queue: [FetchResult]) { self.queue = queue }

    func fetch(token: String) async -> FetchResult {
        lock.withLock {
            tokensSeen.append(token)
            return queue.count > 1 ? queue.removeFirst() : queue[0]
        }
    }
}

struct AccountPollerTests {
    let account = Account(name: "work", configDir: "~/.claude/work")
    let usage = Usage(session: UsageWindow(utilization: 10, resetsAt: nil), weekly: nil)

    @Test func successReturnsOk() async {
        let poller = AccountPoller(tokens: StubTokens([.success(Credential(accessToken: "t1"))]), fetcher: StubFetcher([.ok(usage)]))

        let outcome = await poller.poll(account, previous: .loading)

        #expect(outcome == PollOutcome(status: .ok(usage), transientFailure: false))
    }

    @Test func missingTokenSkipsFetch() async {
        let fetcher = StubFetcher([.ok(usage)])
        let poller = AccountPoller(tokens: StubTokens([.failure(.notFound)]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .loading)

        #expect(outcome == PollOutcome(status: .missing, transientFailure: false))
        #expect(fetcher.tokensSeen.isEmpty)
    }

    @Test func deniedTokenIsMissing() async {
        let poller = AccountPoller(tokens: StubTokens([.failure(.accessDenied)]), fetcher: StubFetcher([.ok(usage)]))
        #expect(await poller.poll(account, previous: .loading).status == .missing)
    }

    @Test func malformedTokenIsError() async {
        let poller = AccountPoller(tokens: StubTokens([.failure(.malformed)]), fetcher: StubFetcher([.ok(usage)]))
        #expect(await poller.poll(account, previous: .loading).status == .error)
    }

    /// 앱은 토큰을 갱신하지 않으므로, 이미 만료된 토큰으로 보내는 요청은 실패가 확정돼 있다.
    /// 계속 보내면 사용량 조회 API가 계정을 429로 차단한다(실제로 발생).
    @Test func expiredCredentialSkipsFetch() async {
        let expired = Credential(accessToken: "t", expiresAt: Date(timeIntervalSince1970: 0))
        let fetcher = StubFetcher([.ok(usage)])
        let poller = AccountPoller(tokens: StubTokens([.success(expired)]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: false))
        #expect(fetcher.tokensSeen.isEmpty)
    }

    @Test func unexpiredCredentialStillFetches() async {
        let valid = Credential(accessToken: "t", expiresAt: Date.now.addingTimeInterval(3600))
        let fetcher = StubFetcher([.ok(usage)])
        let poller = AccountPoller(tokens: StubTokens([.success(valid)]), fetcher: fetcher)

        #expect(await poller.poll(account, previous: .loading).status == .ok(usage))
        #expect(fetcher.tokensSeen == ["t"])
    }

    /// 만료 시각이 없는 옛 자격증명이나 시계 오차로 서버가 401을 주는 경우에도, 같은 주기로
    /// 계속 두드리면 안 된다. 백오프가 필요한 실패로 보고한다.
    @Test func serverUnauthorizedAsksForBackoff() async {
        let poller = AccountPoller(
            tokens: StubTokens([.success(Credential(accessToken: "t"))]), fetcher: StubFetcher([.unauthorized]))

        #expect(await poller.poll(account, previous: .ok(usage)).transientFailure == true)
    }

    @Test func unauthorizedRereadsTokenAndRetriesOnce() async {
        let tokens = StubTokens([.success(Credential(accessToken: "old")), .success(Credential(accessToken: "new"))])
        let fetcher = StubFetcher([.unauthorized, .ok(usage)])
        let poller = AccountPoller(tokens: tokens, fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .expired)

        #expect(outcome.status == .ok(usage))
        #expect(fetcher.tokensSeen == ["old", "new"])
        #expect(tokens.calls == 2)
    }

    @Test func unauthorizedTwiceIsExpired() async {
        // 재조회한 토큰이 원래 토큰과 같으면 다시 fetch하지 않는다.
        let fetcher = StubFetcher([.unauthorized])
        let poller = AccountPoller(tokens: StubTokens([.success(Credential(accessToken: "t"))]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: true))
        #expect(fetcher.tokensSeen == ["t"])
    }

    @Test func unauthorizedWithRefreshedTokenReadFailureDoesNotRetry() async {
        let tokens = StubTokens([.success(Credential(accessToken: "old")), .failure(.accessDenied)])
        let fetcher = StubFetcher([.unauthorized])
        let poller = AccountPoller(tokens: tokens, fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: true))
        #expect(fetcher.tokensSeen == ["old"])
        #expect(tokens.calls == 2)
    }

    @Test func failedReportsTransientFailure() async {
        let poller = AccountPoller(tokens: StubTokens([.success(Credential(accessToken: "t"))]), fetcher: StubFetcher([.failed]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .stale(usage), transientFailure: true))
    }

    @Test func rateLimitedKeepsStaleAndReportsTransientFailure() async {
        let poller = AccountPoller(
            tokens: StubTokens([.success(Credential(accessToken: "t"))]), fetcher: StubFetcher([.rateLimited(retryAfter: nil)]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .stale(usage), transientFailure: true))
    }

    @Test func rateLimitedWithRetryAfterIsCarriedOnOutcome() async {
        let poller = AccountPoller(
            tokens: StubTokens([.success(Credential(accessToken: "t"))]), fetcher: StubFetcher([.rateLimited(retryAfter: 3544)]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome.retryAfter == 3544)
        #expect(outcome.transientFailure == true)
    }
}
