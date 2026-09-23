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
    }

    /// 만료된 토큰으로 조회하다 429를 받으면, "조회 일시 제한"이 "만료"를 가려
    /// 사용자가 재로그인이 필요하다는 사실을 알 수 없게 된다. 만료 상태는 유지한다.
    @Test func expiredSurvivesTransientFailure() {
        #expect(StatusReducer.next(previous: .expired, result: .rateLimited(retryAfter: nil)) == .expired)
        #expect(StatusReducer.next(previous: .expired, result: .failed) == .expired)
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

    @Test func maxRetryAfterConstantIsSingleSource() {
        #expect(PollSchedule.maxRetryAfter == 7200)
        #expect(PollSchedule.nextDelay(backoff: 1, retryAfter: 99999) == PollSchedule.maxRetryAfter)
    }

    // MARK: - I2: 재시작 시 첫 조회 지연

    @Test func initialDelayIsZeroWithoutCachedState() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PollSchedule.initialDelay(now: now, lastSuccessAt: nil, blockedUntil: nil, interval: 180) == 0)
    }

    @Test func initialDelayWaitsUntilLastSuccessPlusIntervalWhenRecent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccessAt = now.addingTimeInterval(-60)
        let delay = PollSchedule.initialDelay(now: now, lastSuccessAt: lastSuccessAt, blockedUntil: nil, interval: 180)
        #expect(delay == 120)
    }

    @Test func initialDelayIsZeroWhenLastSuccessIsOlderThanInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccessAt = now.addingTimeInterval(-200)
        let delay = PollSchedule.initialDelay(now: now, lastSuccessAt: lastSuccessAt, blockedUntil: nil, interval: 180)
        #expect(delay == 0)
    }

    @Test func initialDelayFollowsBlockedUntilWhenFuture() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let blockedUntil = now.addingTimeInterval(500)
        let delay = PollSchedule.initialDelay(now: now, lastSuccessAt: nil, blockedUntil: blockedUntil, interval: 180)
        #expect(delay == 500)
    }

    @Test func initialDelayIsZeroWhenBlockedUntilIsPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let blockedUntil = now.addingTimeInterval(-1)
        let delay = PollSchedule.initialDelay(now: now, lastSuccessAt: nil, blockedUntil: blockedUntil, interval: 180)
        #expect(delay == 0)
    }

    @Test func initialDelayUsesLongerOfBlockedUntilAndLastSuccessWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccessAt = now.addingTimeInterval(-60) // + interval(180) = now+120
        let blockedUntil = now.addingTimeInterval(30) // shorter than 120
        let delay = PollSchedule.initialDelay(
            now: now, lastSuccessAt: lastSuccessAt, blockedUntil: blockedUntil, interval: 180)
        #expect(delay == 120)
    }

    // MARK: - I2: 캐시된 값을 .ok로 보여줄지 판단

    @Test func initialStatusIsLoadingWithoutCachedUsage() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PollSchedule.initialStatus(cachedUsage: nil, lastSuccessAt: nil, now: now, interval: 180) == .loading)
    }

    @Test func initialStatusIsOkWhenLastSuccessIsWithinInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccessAt = now.addingTimeInterval(-60)
        let status = PollSchedule.initialStatus(
            cachedUsage: usage, lastSuccessAt: lastSuccessAt, now: now, interval: 180)
        #expect(status == .ok(usage))
    }

    @Test func initialStatusIsStaleWhenLastSuccessIsOutsideInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccessAt = now.addingTimeInterval(-200)
        let status = PollSchedule.initialStatus(
            cachedUsage: usage, lastSuccessAt: lastSuccessAt, now: now, interval: 180)
        #expect(status == .stale(usage))
    }

    @Test func initialStatusIsStaleWhenNoLastSuccessRecorded() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let status = PollSchedule.initialStatus(cachedUsage: usage, lastSuccessAt: nil, now: now, interval: 180)
        #expect(status == .stale(usage))
    }

    // MARK: - I3: refreshAll이 과도하게 조회하지 않도록 하는 판단

    @Test func shouldRefreshIsTrueWithoutBlockOrRecentPoll() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(PollSchedule.shouldRefresh(now: now, blockedUntil: nil, lastPollStartedAt: nil))
    }

    @Test func shouldRefreshIsFalseWhileBlocked() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let blockedUntil = now.addingTimeInterval(10)
        #expect(!PollSchedule.shouldRefresh(now: now, blockedUntil: blockedUntil, lastPollStartedAt: nil))
    }

    @Test func shouldRefreshIsTrueWhenBlockedUntilIsPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let blockedUntil = now.addingTimeInterval(-1)
        #expect(PollSchedule.shouldRefresh(now: now, blockedUntil: blockedUntil, lastPollStartedAt: nil))
    }

    @Test func shouldRefreshIsFalseWhenLastPollStartedRecently() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastPollStartedAt = now.addingTimeInterval(-10)
        #expect(!PollSchedule.shouldRefresh(now: now, blockedUntil: nil, lastPollStartedAt: lastPollStartedAt))
    }

    @Test func shouldRefreshIsTrueWhenLastPollStartedLongAgo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastPollStartedAt = now.addingTimeInterval(-31)
        #expect(PollSchedule.shouldRefresh(now: now, blockedUntil: nil, lastPollStartedAt: lastPollStartedAt))
    }

    @Test func mostCriticalPicksLowerOfTwoValues() {
        #expect(RemainingPercent.mostCritical(80, 30) == 30)
        #expect(RemainingPercent.mostCritical(30, 80) == 30)
    }

    @Test func mostCriticalIgnoresMissingValues() {
        #expect(RemainingPercent.mostCritical(42, nil) == 42)
        #expect(RemainingPercent.mostCritical(nil, 42) == 42)
    }

    @Test func mostCriticalIsNilWhenAllMissing() {
        #expect(RemainingPercent.mostCritical(nil, nil) == nil)
    }

    @Test func mostCriticalHandlesTies() {
        #expect(RemainingPercent.mostCritical(50, 50) == 50)
    }
}
