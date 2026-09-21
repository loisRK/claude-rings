import Foundation

public struct PollOutcome: Equatable, Sendable {
    public let status: AccountStatus
    /// 429·네트워크 오류처럼 백오프가 필요한 실패인지
    public let transientFailure: Bool
    /// 429 응답의 Retry-After(초). 정수 초로 파싱된 경우에만 값이 있다.
    public let retryAfter: TimeInterval?

    public init(status: AccountStatus, transientFailure: Bool, retryAfter: TimeInterval? = nil) {
        self.status = status
        self.transientFailure = transientFailure
        self.retryAfter = retryAfter
    }
}

public struct AccountPoller: Sendable {
    private let tokens: any TokenProvider
    private let fetcher: any UsageFetching

    public init(tokens: any TokenProvider, fetcher: any UsageFetching) {
        self.tokens = tokens
        self.fetcher = fetcher
    }

    public func poll(_ account: Account, previous: AccountStatus) async -> PollOutcome {
        let token: String
        do {
            token = try tokens.accessToken(for: account)
        } catch {
            return PollOutcome(status: error == .malformed ? .error : .missing, transientFailure: false)
        }

        var result = await fetcher.fetch(token: token)
        // Claude Code가 그 사이 토큰을 갱신했을 수 있으므로 Keychain을 다시 읽어 한 번만 재시도한다.
        // 재조회한 토큰이 원래 토큰과 같으면(즉 갱신되지 않았으면) 다시 호출해 봐야 결과가
        // 같을 것이므로 재시도하지 않는다.
        if result == .unauthorized, let refreshed = try? tokens.accessToken(for: account), refreshed != token {
            result = await fetcher.fetch(token: refreshed)
        }

        let transientFailure: Bool
        let retryAfter: TimeInterval?
        switch result {
        case .rateLimited(let value):
            transientFailure = true
            retryAfter = value
        case .failed:
            transientFailure = true
            retryAfter = nil
        case .ok, .unauthorized:
            transientFailure = false
            retryAfter = nil
        }

        return PollOutcome(
            status: StatusReducer.next(previous: previous, result: result),
            transientFailure: transientFailure,
            retryAfter: retryAfter)
    }
}
