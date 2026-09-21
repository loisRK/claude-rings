import Foundation

/// 계정별로 마지막 성공한 사용량과 조회 스케줄링 상태(마지막 성공 시각, 429 조회 일시 제한
/// 해제 시각)를 디스크에 남긴다.
///
/// Task 8 후속 디버깅에서 확인된 문제: 콜드 스타트 직후 첫 조회가 실패하면(예: API 429),
/// `previous`에 사용량이 전혀 없어 `StatusReducer`가 `.error`로 판정하고 화면은 `-1 / -1`을
/// 계속 보여준다. 이 캐시로 초기 상태를 `.loading` 대신 `.stale(마지막 값)`로 채우면,
/// 같은 실패에도 이미 테스트된 `StatusReducer.next` 규칙(사용량이 있으면 `.stale`, 없으면
/// `.error`)에 따라 실제 숫자가 계속 보이고, 다음 조회가 성공하면 `.ok`로 갱신된다.
///
/// I2: 재시작 후에도 조회 일시 제한(`blockedUntil`)과 마지막 성공 시각(`lastSuccessAt`)을
/// 이어받아 스케줄링(`PollSchedule.initialDelay`/`initialStatus`)에 쓸 수 있게 한다.
public enum UsageCache {
    public static let fileURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches")
        return base.appending(path: "claude-rings/last-usage.json")
    }()

    public struct AccountState: Equatable, Sendable {
        public var usage: Usage?
        public var lastSuccessAt: Date?
        public var blockedUntil: Date?

        public init(usage: Usage? = nil, lastSuccessAt: Date? = nil, blockedUntil: Date? = nil) {
            self.usage = usage
            self.lastSuccessAt = lastSuccessAt
            self.blockedUntil = blockedUntil
        }
    }

    /// `Usage`/`UsageWindow`는 Codable이 아니므로 캐시 전용으로 필드를 그대로 옮겨 담는다.
    /// 기존 파일에는 없던 `lastSuccessAt`/`blockedUntil`은 옵셔널이라 없으면 nil로 디코딩된다.
    private struct Entry: Codable {
        var sessionUtilization: Double?
        var sessionResetsAt: Date?
        var weeklyUtilization: Double?
        var weeklyResetsAt: Date?
        var lastSuccessAt: Date?
        var blockedUntil: Date?
    }

    public static func load(fileURL: URL = UsageCache.fileURL, now: Date = .now) -> [String: AccountState] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries.mapValues { entry in
            let usage: Usage? =
                (entry.sessionUtilization != nil || entry.weeklyUtilization != nil)
                ? Usage(
                    session: entry.sessionUtilization.map {
                        UsageWindow(utilization: $0, resetsAt: entry.sessionResetsAt)
                    },
                    weekly: entry.weeklyUtilization.map {
                        UsageWindow(utilization: $0, resetsAt: entry.weeklyResetsAt)
                    }
                ).clearingExpiredWindows(now: now)
                : nil
            return AccountState(usage: usage, lastSuccessAt: entry.lastSuccessAt, blockedUntil: entry.blockedUntil)
        }
    }

    public static func save(_ states: [String: AccountState], fileURL: URL = UsageCache.fileURL) {
        let entries = states.mapValues { state in
            Entry(
                sessionUtilization: state.usage?.session?.utilization,
                sessionResetsAt: state.usage?.session?.resetsAt,
                weeklyUtilization: state.usage?.weekly?.utilization,
                weeklyResetsAt: state.usage?.weekly?.resetsAt,
                lastSuccessAt: state.lastSuccessAt,
                blockedUntil: state.blockedUntil)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
