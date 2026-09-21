import Foundation

public enum FetchResult: Equatable, Sendable {
    case ok(Usage)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case failed
}

public protocol UsageFetching: Sendable {
    func fetch(token: String) async -> FetchResult
}

public struct UsageClient: UsageFetching {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession = UsageClient.makeSession()) {
        self.session = session
    }

    /// 토큰이 담긴 응답이 디스크에 남지 않도록 캐시·쿠키를 전부 끈 세션을 만든다.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    public static func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(
            url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-rings/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func interpret(status: Int, data: Data, retryAfter: String? = nil) -> FetchResult {
        switch status {
        case 200: UsageParser.parse(data).map(FetchResult.ok) ?? .failed
        case 401, 403: .unauthorized
        case 429: .rateLimited(retryAfter: retryAfter.flatMap { Int($0).map(TimeInterval.init) })
        default: .failed
        }
    }

    public func fetch(token: String) async -> FetchResult {
        do {
            let (data, response) = try await session.data(for: Self.makeRequest(token: token))
            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? 0
            let retryAfter = httpResponse?.value(forHTTPHeaderField: "Retry-After")
            return Self.interpret(status: status, data: data, retryAfter: retryAfter)
        } catch {
            return .failed
        }
    }
}
