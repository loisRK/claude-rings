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
    /// 만료 몇 초 전부터 스스로 갱신할지. Claude Code는 만료 300초 전부터 갱신하므로,
    /// 그보다 늦게 잡아 CLI가 떠 있으면 CLI에 양보한다(동시 갱신 경쟁을 줄인다).
    public static let refreshLeadTime: TimeInterval = 60

    private let tokens: any TokenProvider
    private let fetcher: any UsageFetching
    private let refresher: (any TokenRefreshing)?
    private let writer: (any CredentialWriting)?

    public init(
        tokens: any TokenProvider, fetcher: any UsageFetching,
        refresher: (any TokenRefreshing)? = nil, writer: (any CredentialWriting)? = nil
    ) {
        self.tokens = tokens
        self.fetcher = fetcher
        self.refresher = refresher
        self.writer = writer
    }

    public func poll(_ account: Account, previous: AccountStatus) async -> PollOutcome {
        var credential: Credential
        do {
            credential = try tokens.credential(for: account)
        } catch {
            return PollOutcome(status: error == .malformed ? .error : .missing, transientFailure: false)
        }

        if needsRefresh(credential, now: Date.now) {
            // 실패하면 기존 자격증명을 그대로 두고 진행한다. 아래 만료 검사가 걸러 준다.
            credential = await refreshing(credential, for: account) ?? credential
        }

        // 만료된 토큰으로 보내는 요청은 실패가 확정돼 있다. 보내지 않고 바로 만료로 표시한다.
        // 계속 보내면 사용량 조회 API가 계정을 429로 차단한다. 백오프는 걸지 않는다 —
        // Claude Code가 토큰을 갱신하면 다음 주기에 곧바로 복귀해야 하기 때문이다.
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

    private func needsRefresh(_ credential: Credential, now: Date) -> Bool {
        guard refresher != nil, writer != nil, credential.refreshToken != nil,
              let expiresAt = credential.expiresAt
        else { return false }
        return expiresAt.timeIntervalSince(now) <= Self.refreshLeadTime
    }

    /// 갱신에 성공하면 새 자격증명을, 실패하면 nil을 돌려준다. Keychain은 성공했을 때만 쓴다.
    private func refreshing(_ credential: Credential, for account: Account) async -> Credential? {
        guard let refresher, let writer, let refreshToken = credential.refreshToken else { return nil }

        guard case .ok(let fresh) = await refresher.refresh(
            refreshToken: refreshToken, scopes: credential.scopes)
        else { return nil }

        // 되쓰기 직전에 Keychain을 다시 읽는다. 그 사이 Claude Code가 먼저 갱신했다면 서버가
        // refresh token을 로테이션했을 수 있고, 그때 우리 응답으로 덮어쓰면 CLI가 저장한
        // 값을 잃어 계정이 재로그인을 요구하게 된다. 저장된 값을 그대로 따른다.
        if let current = try? tokens.credential(for: account),
           current.refreshToken != credential.refreshToken {
            return current
        }

        let now = Date.now
        guard let updated = CredentialJSON.applying(fresh, to: credential.raw, now: now),
              writer.write(updated, for: account)
        else { return nil }

        return Credential(
            accessToken: fresh.accessToken,
            expiresAt: now.addingTimeInterval(fresh.expiresIn),
            refreshToken: fresh.refreshToken ?? refreshToken,
            scopes: credential.scopes,
            raw: updated)
    }
}
