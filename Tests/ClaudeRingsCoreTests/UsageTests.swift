import Foundation
import Testing
@testable import ClaudeRingsCore

let sampleUsageJSON = """
{
  "five_hour": { "utilization": 24.0, "resets_at": "2026-09-18T10:00:00.123456+00:00" },
  "seven_day": { "utilization": 20, "resets_at": "2026-09-20T03:00:00+00:00" },
  "seven_day_opus": null,
  "extra_usage": null
}
"""

struct UsageTests {
    @Test func parsesSessionAndWeekly() throws {
        let usage = try #require(UsageParser.parse(Data(sampleUsageJSON.utf8)))

        #expect(usage.session?.utilization == 24.0)
        #expect(usage.session?.remainingPercent == 76)
        #expect(usage.weekly?.remainingPercent == 80)
    }

    @Test func parsesResetDatesWithAndWithoutFraction() throws {
        let usage = try #require(UsageParser.parse(Data(sampleUsageJSON.utf8)))
        let session = try #require(usage.session?.resetsAt)
        let weekly = try #require(usage.weekly?.resetsAt)

        #expect(abs(session.timeIntervalSince1970 - 1_789_725_600.123) < 0.01)
        #expect(weekly.timeIntervalSince1970 == 1_789_873_200)
    }

    @Test func missingOrNullWindowsBecomeNil() throws {
        let usage = try #require(UsageParser.parse(Data(#"{"five_hour":null}"#.utf8)))

        #expect(usage.session == nil)
        #expect(usage.weekly == nil)
    }

    @Test func missingResetDateIsNil() throws {
        let usage = try #require(UsageParser.parse(Data(#"{"five_hour":{"utilization":10}}"#.utf8)))

        #expect(usage.session?.remainingPercent == 90)
        #expect(usage.session?.resetsAt == nil)
    }

    @Test func nonObjectReturnsNil() {
        #expect(UsageParser.parse(Data("[1,2]".utf8)) == nil)
        #expect(UsageParser.parse(Data("not json".utf8)) == nil)
    }

    @Test(arguments: [(0.0, 100), (0.4, 100), (99.6, 0), (120.0, 0), (-5.0, 100), (50.5, 50)])
    func remainingPercentIsRoundedAndClamped(utilization: Double, expected: Int) {
        #expect(UsageWindow(utilization: utilization, resetsAt: nil).remainingPercent == expected)
    }

    // MARK: - M5: 리셋 시각이 지난 창은 오래된 값으로 취급

    @Test func clearingExpiredWindowsNilsOutPastResetsAt() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let usage = Usage(
            session: UsageWindow(utilization: 10, resetsAt: now.addingTimeInterval(-1)),
            weekly: UsageWindow(utilization: 20, resetsAt: now.addingTimeInterval(100)))

        let cleared = usage.clearingExpiredWindows(now: now)

        #expect(cleared.session == nil)
        #expect(cleared.weekly == usage.weekly)
    }

    @Test func clearingExpiredWindowsKeepsWindowsWithoutResetDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let usage = Usage(session: UsageWindow(utilization: 10, resetsAt: nil), weekly: nil)

        #expect(usage.clearingExpiredWindows(now: now) == usage)
    }
}
