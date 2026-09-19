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
        case .rateLimited, .failed: previous.usage.map(AccountStatus.stale) ?? .error
        }
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
