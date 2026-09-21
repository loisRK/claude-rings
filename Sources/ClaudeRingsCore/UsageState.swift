import Foundation

public enum AccountStatus: Equatable, Sendable {
    case loading
    case ok(Usage)
    case stale(Usage)
    case expired
    case missing
    case error

    public var usage: Usage? {
        switch self {
        case .ok(let usage), .stale(let usage): usage
        default: nil
        }
    }
}

public enum RingLevel: Equatable, Sendable {
    case good, warning, critical, unavailable

    public init(remaining: Int?) {
        switch remaining {
        case nil: self = .unavailable
        case let value? where value >= 50: self = .good
        case let value? where value >= 20: self = .warning
        default: self = .critical
        }
    }
}

public enum StatusReducer {
    public static func next(previous: AccountStatus, result: FetchResult) -> AccountStatus {
        switch result {
        case .ok(let usage): .ok(usage)
        case .unauthorized: .expired
        case .rateLimited(_), .failed: previous.usage.map(AccountStatus.stale) ?? .error
        }
    }
}

/// 서버의 Retry-After 지시와 로컬 백오프 중 더 긴 쪽을 따르되, 상한을 둔다.
public enum PollSchedule {
    /// Retry-After로 기다릴 수 있는 최대 시간(초). 다른 곳에서 이 값을 다시 정의하지 않도록 여기 하나만 둔다.
    public static let maxRetryAfter: TimeInterval = 7200

    public static func nextDelay(backoff: TimeInterval, retryAfter: TimeInterval?) -> TimeInterval {
        max(backoff, min(retryAfter ?? 0, maxRetryAfter))
    }

    /// 재시작 직후 계정별 첫 조회를 언제 시작할지(I2). `blockedUntil`과
    /// `lastSuccessAt + interval` 중 더 늦은 시각까지 기다리고, 둘 다 과거면 즉시 조회한다.
    public static func initialDelay(
        now: Date, lastSuccessAt: Date?, blockedUntil: Date?, interval: TimeInterval
    ) -> TimeInterval {
        var target = blockedUntil
        if let lastSuccessAt {
            let candidate = lastSuccessAt.addingTimeInterval(interval)
            if target == nil || candidate > target! { target = candidate }
        }
        guard let target, target > now else { return 0 }
        return target.timeIntervalSince(now)
    }

    /// 재시작 직후 캐시된 값을 어떤 상태로 보여줄지(I2). 마지막 성공이 조회 주기 이내면
    /// 아직 유효한 값이므로 `.ok`로, 그렇지 않으면(또는 기록이 없으면) `.stale`로 보여준다.
    public static func initialStatus(
        cachedUsage: Usage?, lastSuccessAt: Date?, now: Date, interval: TimeInterval
    ) -> AccountStatus {
        guard let cachedUsage else { return .loading }
        if let lastSuccessAt, now.timeIntervalSince(lastSuccessAt) < interval {
            return .ok(cachedUsage)
        }
        return .stale(cachedUsage)
    }

    /// 수동 새로고침이 과도하게 조회하지 않도록 하는 판단(I3): 조회 일시 제한 중이거나
    /// 마지막 조회 시작이 `minInterval` 이내면 건너뛴다.
    public static func shouldRefresh(
        now: Date, blockedUntil: Date?, lastPollStartedAt: Date?, minInterval: TimeInterval = 30
    ) -> Bool {
        if let blockedUntil, blockedUntil > now { return false }
        if let lastPollStartedAt, now.timeIntervalSince(lastPollStartedAt) < minInterval { return false }
        return true
    }
}

public struct Backoff: Equatable, Sendable {
    public let base: TimeInterval
    public let maximum: TimeInterval
    public private(set) var failures = 0

    public init(base: TimeInterval, maximum: TimeInterval = 900) {
        self.base = base
        self.maximum = maximum
    }

    public var interval: TimeInterval {
        min(maximum, base * pow(2, Double(failures)))
    }

    public mutating func recordFailure() {
        failures = min(failures + 1, 16)
    }

    public mutating func recordSuccess() {
        failures = 0
    }
}

public enum ResetFormatter {
    public static func string(until date: Date, now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "곧" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}
