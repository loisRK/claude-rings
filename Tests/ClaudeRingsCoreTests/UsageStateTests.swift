import Foundation
import Testing
@testable import ClaudeRingsCore

struct UsageStateTests {
    let usage = Usage(session: UsageWindow(utilization: 24, resetsAt: nil), weekly: nil)

    @Test(arguments: [
        (100, RingLevel.good), (50, .good), (49, .warning), (20, .warning), (19, .critical), (0, .critical),
    ])
    func ringLevelThresholds(remaining: Int, expected: RingLevel) {
        #expect(RingLevel(remaining: remaining) == expected)
    }

    @Test func ringLevelWithoutValueIsUnavailable() {
        #expect(RingLevel(remaining: nil) == .unavailable)
    }

    @Test func okResultBecomesOk() {
        #expect(StatusReducer.next(previous: .loading, result: .ok(usage)) == .ok(usage))
    }

    @Test func unauthorizedBecomesExpired() {
        #expect(StatusReducer.next(previous: .ok(usage), result: .unauthorized) == .expired)
    }

    @Test func transientFailureKeepsPreviousUsageAsStale() {
        #expect(StatusReducer.next(previous: .ok(usage), result: .rateLimited(retryAfter: nil)) == .stale(usage))
        #expect(StatusReducer.next(previous: .ok(usage), result: .rateLimited(retryAfter: 3544)) == .stale(usage))
        #expect(StatusReducer.next(previous: .stale(usage), result: .failed) == .stale(usage))
    }

    @Test func transientFailureWithoutUsageIsError() {
        #expect(StatusReducer.next(previous: .loading, result: .failed) == .error)
        #expect(StatusReducer.next(previous: .expired, result: .rateLimited(retryAfter: nil)) == .error)
    }

    @Test func backoffDoublesUpToMaximumAndResets() {
        var backoff = Backoff(base: 180)
        #expect(backoff.interval == 180)
        backoff.recordFailure()
        #expect(backoff.interval == 360)
        backoff.recordFailure()
        #expect(backoff.interval == 720)
        backoff.recordFailure()
        #expect(backoff.interval == 900)
        for _ in 0..<100 { backoff.recordFailure() }
        #expect(backoff.interval == 900)
        backoff.recordSuccess()
        #expect(backoff.interval == 180)
    }

    @Test(arguments: [
        (2 * 3600 + 51 * 60, "2h 51m"),
        (39 * 3600, "1d 15h"),
        (12 * 60 + 30, "12m"),
        (20, "1m"),
        (0, "곧"),
        (-100, "곧"),
    ] as [(Int, String)])
    func resetFormatting(seconds: Int, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ResetFormatter.string(until: now.addingTimeInterval(TimeInterval(seconds)), now: now) == expected)
    }

    @Test(arguments: [
        (180.0, nil, 180.0),
        (180.0, 3544.0, 3544.0),
        (900.0, 60.0, 900.0),
        (180.0, 99999.0, 7200.0),
    ] as [(TimeInterval, TimeInterval?, TimeInterval)])
    func pollScheduleFollowsRetryAfterWithUpperBound(
        backoff: TimeInterval, retryAfter: TimeInterval?, expected: TimeInterval
    ) {
        #expect(PollSchedule.nextDelay(backoff: backoff, retryAfter: retryAfter) == expected)
    }
}
