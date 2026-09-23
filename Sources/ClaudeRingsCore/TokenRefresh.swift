import Foundation

/// OAuth 갱신 응답. 서버가 refresh token을 로테이션하면 새 값이 함께 온다.
public struct RefreshedTokens: Equatable, Sendable {
    public let accessToken: String
    /// 응답에 없으면 nil. 이때는 저장된 기존 refresh token을 계속 쓴다.
    public let refreshToken: String?
    public let expiresIn: TimeInterval
    public let refreshTokenExpiresIn: TimeInterval?

    public init(
        accessToken: String, refreshToken: String?, expiresIn: TimeInterval,
        refreshTokenExpiresIn: TimeInterval?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
    }
}

/// Keychain에 저장된 자격증명 JSON을 다룬다. Claude Code가 쓰는 필드를 전부 알 수 없으므로
/// 구조체로 파싱했다가 다시 인코딩하지 않고, 필요한 키만 바꿔 넣어 나머지를 그대로 보존한다.
public enum CredentialJSON {
    static let oauthKey = "claudeAiOauth"

    public static func applying(_ tokens: RefreshedTokens, to raw: Data, now: Date) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              var oauth = object[oauthKey] as? [String: Any]
        else { return nil }

        oauth["accessToken"] = tokens.accessToken
        oauth["expiresAt"] = milliseconds(from: now, adding: tokens.expiresIn)
        if let refreshToken = tokens.refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        if let ttl = tokens.refreshTokenExpiresIn {
            oauth["refreshTokenExpiresAt"] = milliseconds(from: now, adding: ttl)
        }
        object[oauthKey] = oauth
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private static func milliseconds(from now: Date, adding seconds: TimeInterval) -> Double {
        (now.timeIntervalSince1970 + seconds) * 1000
    }
}

public enum RefreshResult: Equatable, Sendable {
    case ok(RefreshedTokens)
    /// refresh token 자체가 무효해진 경우. 앱이 복구할 수 없고 재로그인이 필요하다.
    case invalidGrant
    /// 네트워크·서버 오류처럼 다시 시도해 볼 만한 실패.
    case failed
}

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String, scopes: [String]) async -> RefreshResult
}

/// Claude Code와 같은 방식으로 access token을 갱신한다. client_secret이 없는 public
/// client라서 refresh token·client_id·scope만 있으면 된다.
public struct OAuthTokenRefresher: TokenRefreshing {
    public static let endpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code의 공개 client id.
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let session: URLSession

    public init(session: URLSession = UsageClient.makeSession()) {
        self.session = session
    }

    public static func makeRequest(refreshToken: String, scopes: [String]) -> URLRequest {
        var request = URLRequest(
            url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-rings/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ])
        return request
    }

    public static func interpret(status: Int, data: Data) -> RefreshResult {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
            let refresh_token_expires_in: Double?
        }
        switch status {
        case 200:
            guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return .failed }
            return .ok(RefreshedTokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token,
                expiresIn: response.expires_in,
                refreshTokenExpiresIn: response.refresh_token_expires_in))
        case 400, 401, 403:
            // 본문이 invalid_grant면 refresh token이 죽은 것이고, 그 밖의 4xx는 일시 오류로 본다.
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.contains("invalid_grant") ? .invalidGrant : .failed
        default:
            return .failed
        }
    }

    public func refresh(refreshToken: String, scopes: [String]) async -> RefreshResult {
        do {
            let (data, response) = try await session.data(
                for: Self.makeRequest(refreshToken: refreshToken, scopes: scopes))
            return Self.interpret(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failed
        }
    }
}
