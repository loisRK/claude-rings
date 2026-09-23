import Foundation

public struct PollOutcome: Equatable, Sendable {
    public let status: AccountStatus
    /// 429·네트워크 오류·401처럼 백오프가 필요한 실패인지
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
        let credential: Credential
        do {
            credential = try tokens.credential(for: account)
        } catch {
            return PollOutcome(status: error == .malformed ? .error : .missing, transientFailure: false)
        }

        // 이 앱은 토큰을 갱신하지 않으므로, 이미 만료된 토큰으로 보내는 요청은 실패가 확정돼
        // 있다. 보내지 않고 바로 만료로 표시한다. 계속 보내면 사용량 조회 API가 계정을
        // 429로 차단한다. 백오프는 걸지 않는다 — Claude Code가 토큰을 갱신하면 다음 주기에
        // 곧바로 복귀해야 하기 때문이다.
        if let expiresAt = credential.expiresAt, expiresAt <= Date.now {
            return PollOutcome(status: .expired, transientFailure: false)
        }

        let token = credential.accessToken
        var result = await fetcher.fetch(token: token)
        // Claude Code가 그 사이 토큰을 갱신했을 수 있으므로 Keychain을 다시 읽어 한 번만 재시도한다.
        // 재조회한 토큰이 원래 토큰과 같으면(즉 갱신되지 않았으면) 다시 호출해 봐야 결과가
        // 같을 것이므로 재시도하지 않는다.
        if result == .unauthorized, let refreshed = try? tokens.credential(for: account).accessToken, refreshed != token {
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
        case .unauthorized:
            // 갱신할 수 없는 토큰이라 같은 주기로 다시 보내봐야 또 401이다. 백오프한다.
            transientFailure = true
            retryAfter = nil
        case .ok:
            transientFailure = false
            retryAfter = nil
        }

        return PollOutcome(
            status: StatusReducer.next(previous: previous, result: result),
            transientFailure: transientFailure,
            retryAfter: retryAfter)
    }
}
