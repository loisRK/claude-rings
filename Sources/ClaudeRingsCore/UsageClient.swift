import Foundation

public enum FetchResult: Equatable, Sendable {
    case ok(Usage)
    case unauthorized
    case rateLimited
    case failed
}

public protocol UsageFetching: Sendable {
    func fetch(token: String) async -> FetchResult
}

public struct UsageClient: UsageFetching {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-rings/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func interpret(status: Int, data: Data) -> FetchResult {
        switch status {
        case 200: UsageParser.parse(data).map(FetchResult.ok) ?? .failed
        case 401, 403: .unauthorized
        case 429: .rateLimited
        default: .failed
        }
    }

    public func fetch(token: String) async -> FetchResult {
        do {
            let (data, response) = try await session.data(for: Self.makeRequest(token: token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.interpret(status: status, data: data)
        } catch {
            return .failed
        }
    }
}
