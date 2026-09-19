import Foundation

public struct PollOutcome: Equatable, Sendable {
    public let status: AccountStatus
    /// 429·네트워크 오류처럼 백오프가 필요한 실패인지
    public let transientFailure: Bool

    public init(status: AccountStatus, transientFailure: Bool) {
        self.status = status
        self.transientFailure = transientFailure
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
        if result == .unauthorized, let refreshed = try? tokens.accessToken(for: account) {
            result = await fetcher.fetch(token: refreshed)
        }

        return PollOutcome(
            status: StatusReducer.next(previous: previous, result: result),
            transientFailure: result == .rateLimited || result == .failed)
    }
}
