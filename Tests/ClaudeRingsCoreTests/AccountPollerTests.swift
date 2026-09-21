import Foundation
import Testing
@testable import ClaudeRingsCore

final class StubTokens: TokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<String, TokenError>]
    private(set) var calls = 0

    init(_ queue: [Result<String, TokenError>]) { self.queue = queue }

    func accessToken(for account: Account) throws(TokenError) -> String {
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
        let poller = AccountPoller(tokens: StubTokens([.success("t1")]), fetcher: StubFetcher([.ok(usage)]))

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

    @Test func unauthorizedRereadsTokenAndRetriesOnce() async {
        let tokens = StubTokens([.success("old"), .success("new")])
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
        let poller = AccountPoller(tokens: StubTokens([.success("t")]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: false))
        #expect(fetcher.tokensSeen == ["t"])
    }

    @Test func unauthorizedWithRefreshedTokenReadFailureDoesNotRetry() async {
        let tokens = StubTokens([.success("old"), .failure(.accessDenied)])
        let fetcher = StubFetcher([.unauthorized])
        let poller = AccountPoller(tokens: tokens, fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: false))
        #expect(fetcher.tokensSeen == ["old"])
        #expect(tokens.calls == 2)
    }

    @Test func failedReportsTransientFailure() async {
        let poller = AccountPoller(tokens: StubTokens([.success("t")]), fetcher: StubFetcher([.failed]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .stale(usage), transientFailure: true))
    }

    @Test func rateLimitedKeepsStaleAndReportsTransientFailure() async {
        let poller = AccountPoller(
            tokens: StubTokens([.success("t")]), fetcher: StubFetcher([.rateLimited(retryAfter: nil)]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .stale(usage), transientFailure: true))
    }

    @Test func rateLimitedWithRetryAfterIsCarriedOnOutcome() async {
        let poller = AccountPoller(
            tokens: StubTokens([.success("t")]), fetcher: StubFetcher([.rateLimited(retryAfter: 3544)]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome.retryAfter == 3544)
        #expect(outcome.transientFailure == true)
    }
}
