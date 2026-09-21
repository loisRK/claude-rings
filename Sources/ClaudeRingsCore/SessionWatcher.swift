import Foundation

public protocol ProcessChecker: Sendable {
    func isAlive(_ pid: Int32) -> Bool
}

public struct KillProcessChecker: ProcessChecker {
    public init() {}

    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public let activeConfigDirs: Set<String>
    public let shouldQuit: Bool
}

/// `~/.claude-rings/sessions/<셸 PID>` 파일(내용: config 경로)로 실행 중인 세션을 추적한다.
public struct SessionWatcher: Sendable {
    public let directory: URL
    private let checker: any ProcessChecker
    private let grace: TimeInterval
    private let home: String
    private var emptySince: Date?

    public init(
        directory: URL = SessionWatcher.defaultDirectory,
        checker: any ProcessChecker = KillProcessChecker(),
        grace: TimeInterval = 10,
        home: String = NSHomeDirectory()
    ) {
        self.directory = directory
        self.checker = checker
        self.grace = grace
        self.home = home
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude-rings/sessions")
    }

    public mutating func tick(now: Date = .now) -> SessionSnapshot {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var active = Set<String>()
        var liveCount = 0

        for name in names {
            guard let pid = Int32(name), pid > 0 else { continue }
            let file = directory.appending(path: name)
            guard checker.isAlive(pid) else {
                try? fileManager.removeItem(at: file)
                continue
            }
            liveCount += 1
            let content = (try? String(contentsOf: file, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !content.isEmpty {
                active.insert(KeychainService.normalize(content, home: home))
            }
        }

        if liveCount > 0 {
            emptySince = nil
            return SessionSnapshot(activeConfigDirs: active, shouldQuit: false)
        }
        let since = emptySince ?? now
        emptySince = since
        return SessionSnapshot(activeConfigDirs: [], shouldQuit: now.timeIntervalSince(since) >= grace)
    }
}
