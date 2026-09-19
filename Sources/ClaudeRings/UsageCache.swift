import ClaudeRingsCore
import Foundation

/// 계정별로 마지막 성공한 사용량을 디스크에 남긴다.
///
/// Task 8 후속 디버깅에서 확인된 문제: 콜드 스타트 직후 첫 조회가 실패하면(예: API 429),
/// `previous`에 사용량이 전혀 없어 `StatusReducer`가 `.error`로 판정하고 화면은 `-1 / -1`을
/// 계속 보여준다. 이 캐시로 초기 상태를 `.loading` 대신 `.stale(마지막 값)`로 채우면,
/// 같은 실패에도 이미 테스트된 `StatusReducer.next` 규칙(사용량이 있으면 `.stale`, 없으면
/// `.error`)에 따라 실제 숫자가 계속 보이고, 다음 조회가 성공하면 `.ok`로 갱신된다.
/// Core는 건드리지 않는다(순수 앱 계층 캐시).
enum UsageCache {
    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches")
        return base.appending(path: "claude-rings/last-usage.json")
    }()

    /// `Usage`/`UsageWindow`는 Codable이 아니므로 캐시 전용으로 필드를 그대로 옮겨 담는다.
    private struct Entry: Codable {
        var sessionUtilization: Double?
        var sessionResetsAt: Date?
        var weeklyUtilization: Double?
        var weeklyResetsAt: Date?
    }

    static func load(fileURL: URL = UsageCache.fileURL) -> [String: Usage] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries.mapValues { entry in
            Usage(
                session: entry.sessionUtilization.map {
                    UsageWindow(utilization: $0, resetsAt: entry.sessionResetsAt)
                },
                weekly: entry.weeklyUtilization.map {
                    UsageWindow(utilization: $0, resetsAt: entry.weeklyResetsAt)
                })
        }
    }

    static func save(_ usages: [String: Usage], fileURL: URL = UsageCache.fileURL) {
        let entries = usages.mapValues { usage in
            Entry(
                sessionUtilization: usage.session?.utilization,
                sessionResetsAt: usage.session?.resetsAt,
                weeklyUtilization: usage.weekly?.utilization,
                weeklyResetsAt: usage.weekly?.resetsAt)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
