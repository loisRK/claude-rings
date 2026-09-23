import Foundation

/// AI 코딩 서비스 식별자(Claude, 추후 다른 서비스). `accounts.json`의 `service` 필드,
/// 로고 에셋 파일명(`logos/<rawValue>.png`)에 그대로 쓰인다.
public struct ServiceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claude = ServiceID(rawValue: "claude")
}

/// 서비스별로 다른 토큰 소스·조회 API를 등록해, 계정의 `service`에 맞는 조합을 고르게 한다.
/// 새 서비스를 추가하려면 `TokenProvider`·`UsageFetching` 구현을 만들어 여기 등록하면 되고,
/// `UsageViewModel` 등 나머지 코드는 바꿀 필요가 없다.
public struct ServiceRegistry: Sendable {
    private struct Entry: Sendable {
        let tokens: any TokenProvider
        let fetcher: any UsageFetching
        let refresher: (any TokenRefreshing)?
        let writer: (any CredentialWriting)?
    }

    private var entries: [ServiceID: Entry] = [:]

    public init() {}

    /// `refresher`와 `writer`를 둘 다 주면 만료가 임박한 토큰을 앱이 스스로 갱신한다.
    /// 하나라도 없으면 갱신하지 않고 읽기만 한다.
    public mutating func register(
        _ id: ServiceID, tokens: any TokenProvider, fetcher: any UsageFetching,
        refresher: (any TokenRefreshing)? = nil, writer: (any CredentialWriting)? = nil
    ) {
        entries[id] = Entry(tokens: tokens, fetcher: fetcher, refresher: refresher, writer: writer)
    }

    /// 등록되지 않은 서비스면 nil(호출부가 "지원하지 않는 서비스"로 표시해야 한다).
    public func poller(for id: ServiceID) -> AccountPoller? {
        guard let entry = entries[id] else { return nil }
        return AccountPoller(
            tokens: entry.tokens, fetcher: entry.fetcher,
            refresher: entry.refresher, writer: entry.writer)
    }

    public func isSupported(_ id: ServiceID) -> Bool {
        entries[id] != nil
    }

    /// Claude만 등록한 기본 레지스트리. 다른 서비스는 아직 구현 전이라 등록하지 않는다.
    /// `refresher`·`writer`를 넘기면 토큰 자동 갱신이 켜진다(호출부가 Keychain 쓰기가
    /// 실제로 되는지 확인한 뒤 넘겨야 한다).
    public static func claudeOnly(
        refresher: (any TokenRefreshing)? = nil, writer: (any CredentialWriting)? = nil
    ) -> ServiceRegistry {
        var registry = ServiceRegistry()
        registry.register(
            .claude, tokens: KeychainTokenProvider(), fetcher: UsageClient(),
            refresher: refresher, writer: writer)
        return registry
    }
}
