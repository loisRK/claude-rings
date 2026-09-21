import Foundation
import Testing
@testable import ClaudeRingsCore

struct FakeChecker: ProcessChecker {
    var alive: Set<Int32>
    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
}

struct SessionWatcherTests {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "claude-rings-sessions-\(UUID().uuidString)")
    let home = "/Users/alice"
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func writeSession(pid: Int32, configDir: String) throws {
        try Data("\(configDir)\n".utf8).write(to: dir.appending(path: "\(pid)"))
    }

    func watcher(alive: Set<Int32>) -> SessionWatcher {
        SessionWatcher(directory: dir, checker: FakeChecker(alive: alive), grace: 10, home: home)
    }

    @Test func collectsNormalizedConfigDirsOfLiveSessions() throws {
        try writeSession(pid: 100, configDir: "~/.claude/work")
        try writeSession(pid: 200, configDir: "/Users/alice/.claude/")
        var sut = watcher(alive: [100, 200])

        let snapshot = sut.tick(now: t0)

        #expect(snapshot.activeConfigDirs == ["/Users/alice/.claude/work", "/Users/alice/.claude"])
        #expect(snapshot.shouldQuit == false)
    }

    @Test func removesFilesOfDeadSessions() throws {
        try writeSession(pid: 100, configDir: "~/.claude/work")
        try writeSession(pid: 300, configDir: "~/.claude")
        var sut = watcher(alive: [100])

        let snapshot = sut.tick(now: t0)

        #expect(snapshot.activeConfigDirs == ["/Users/alice/.claude/work"])
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "300").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "100").path))
    }

    @Test func ignoresNonNumericFiles() throws {
        try Data("x".utf8).write(to: dir.appending(path: ".DS_Store"))
        var sut = watcher(alive: [])

        _ = sut.tick(now: t0)

        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".DS_Store").path))
    }

    @Test func quitsOnlyAfterGracePeriodWithNoSessions() {
        var sut = watcher(alive: [])

        #expect(sut.tick(now: t0).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(5)).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(10)).shouldQuit == true)
    }

    @Test func newSessionResetsGracePeriod() throws {
        var sut = watcher(alive: [100])

        _ = sut.tick(now: t0)
        try writeSession(pid: 100, configDir: "~/.claude")
        #expect(sut.tick(now: t0.addingTimeInterval(8)).shouldQuit == false)
        try FileManager.default.removeItem(at: dir.appending(path: "100"))
        #expect(sut.tick(now: t0.addingTimeInterval(12)).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(22)).shouldQuit == true)
    }

    @Test func ignoresNonPositivePIDs() throws {
        try writeSession(pid: 0, configDir: "~/.claude")
        try writeSession(pid: -100, configDir: "~/.claude/work")
        var sut = watcher(alive: [0, -100])

        let snapshot = sut.tick(now: t0)

        #expect(snapshot.activeConfigDirs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "0").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "-100").path))
    }

    @Test func missingDirectoryCountsAsNoSessions() {
        var sut = SessionWatcher(
            directory: dir.appending(path: "nope"), checker: FakeChecker(alive: []), grace: 0, home: home)
        #expect(sut.tick(now: t0).shouldQuit == true)
    }
}
