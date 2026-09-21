import Foundation

public struct UsageWindow: Equatable, Sendable {
    /// 사용률(0~100)
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// 남은 비율(0~100, 정수)
    public var remainingPercent: Int {
        max(0, min(100, Int((100 - utilization).rounded())))
    }
}

public struct Usage: Equatable, Sendable {
    public var session: UsageWindow?
    public var weekly: UsageWindow?

    public init(session: UsageWindow?, weekly: UsageWindow?) {
        self.session = session
        self.weekly = weekly
    }

    /// 리셋 시각이 이미 지난 창은 다음 조회 전까지도 오래된 값이므로 없는 것으로 취급한다(M5).
    /// 화면은 이 값을 "—"로 표시하게 된다.
    public func clearingExpiredWindows(now: Date = .now) -> Usage {
        func clear(_ window: UsageWindow?) -> UsageWindow? {
            guard let window, let resetsAt = window.resetsAt, resetsAt <= now else { return window }
            return nil
        }
        return Usage(session: clear(session), weekly: clear(weekly))
    }
}

/// 비공식 API라 스키마가 바뀔 수 있으므로 필드별로 관대하게 파싱한다.
public enum UsageParser {
    public static func parse(_ data: Data) -> Usage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return Usage(session: window(root["five_hour"]), weekly: window(root["seven_day"]))
    }

    static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return UsageWindow(
            utilization: utilization,
            resetsAt: (dict["resets_at"] as? String).flatMap(parseDate))
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        // 마이크로초(6자리) 등 포매터가 못 읽는 소수부는 밀리초로 줄여 다시 시도한다.
        guard let dot = string.firstIndex(of: "."),
              let end = string[dot...].firstIndex(where: { !$0.isNumber && $0 != "." })
        else { return nil }
        let fraction = string[string.index(after: dot)..<end].prefix(3)
        let trimmed = string[..<dot] + "." + fraction + string[end...]
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(trimmed))
    }
}
