import Foundation
import Testing
@testable import ClaudeRingsCore

struct UsageCacheTests {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "claude-rings-cache-tests-\(UUID().uuidString)")
    var fileURL: URL { dir.appending(path: "last-usage.json") }
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func loadReturnsEmptyWhenFileMissing() {
        #expect(UsageCache.load(fileURL: fileURL) == [:])
    }

    @Test func savedStateRoundTripsThroughLoad() {
        let usage = Usage(
            session: UsageWindow(utilization: 24, resetsAt: now.addingTimeInterval(3600)),
            weekly: UsageWindow(utilization: 10, resetsAt: now.addingTimeInterval(86400)))
        let state = UsageCache.AccountState(
            usage: usage, lastSuccessAt: now.addingTimeInterval(-30), blockedUntil: now.addingTimeInterval(120))
        UsageCache.save(["work": state], fileURL: fileURL)

        let loaded = UsageCache.load(fileURL: fileURL, now: now)

        #expect(loaded["work"] == state)
    }

    @Test func loadClearsWindowsWhoseResetHasPassed() {
        let usage = Usage(
            session: UsageWindow(utilization: 24, resetsAt: now.addingTimeInterval(-1)),
            weekly: UsageWindow(utilization: 10, resetsAt: now.addingTimeInterval(86400)))
        UsageCache.save(["work": UsageCache.AccountState(usage: usage)], fileURL: fileURL)

        let loaded = UsageCache.load(fileURL: fileURL, now: now)

        #expect(loaded["work"]?.usage?.session == nil)
        #expect(loaded["work"]?.usage?.weekly == usage.weekly)
    }

    @Test func loadDecodesOldFormatFileWithoutSchedulingFields() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"""
        {"work":{"sessionUtilization":24,"weeklyUtilization":10}}
        """#
        try Data(json.utf8).write(to: fileURL)

        let loaded = UsageCache.load(fileURL: fileURL, now: now)

        #expect(loaded["work"]?.usage?.session?.utilization == 24)
        #expect(loaded["work"]?.usage?.weekly?.utilization == 10)
        #expect(loaded["work"]?.lastSuccessAt == nil)
        #expect(loaded["work"]?.blockedUntil == nil)
    }

    @Test func loadIgnoresCorruptFile() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(UsageCache.load(fileURL: fileURL) == [:])
    }

    @Test func saveWritesReadableFileAtGivenPath() {
        UsageCache.save(["main": UsageCache.AccountState()], fileURL: fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
