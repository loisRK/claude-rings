import Foundation
import Testing
@testable import ClaudeRingsCore

struct TokenRefresherTests {
    @Test func requestMatchesClaudeCodeOAuthRefresh() throws {
        let request = OAuthTokenRefresher.makeRequest(refreshToken: "r-1", scopes: ["user:profile", "user:inference"])

        #expect(request.url == URL(string: "https://platform.claude.com/v1/oauth/token"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["grant_type"] as? String == "refresh_token")
        #expect(object["refresh_token"] as? String == "r-1")
        #expect(object["client_id"] as? String == OAuthTokenRefresher.clientID)
        #expect(object["scope"] as? String == "user:profile user:inference")
    }

    @Test func successYieldsTokens() {
        let data = Data(#"{"access_token":"a-new","expires_in":28800}"#.utf8)

        #expect(OAuthTokenRefresher.interpret(status: 200, data: data)
            == .ok(RefreshedTokens(accessToken: "a-new", refreshToken: nil, expiresIn: 28800, refreshTokenExpiresIn: nil)))
    }

    @Test func rotatedRefreshTokenIsCarried() {
        let data = Data(#"{"access_token":"a","refresh_token":"r-2","expires_in":60,"refresh_token_expires_in":120}"#.utf8)

        #expect(OAuthTokenRefresher.interpret(status: 200, data: data)
            == .ok(RefreshedTokens(accessToken: "a", refreshToken: "r-2", expiresIn: 60, refreshTokenExpiresIn: 120)))
    }

    /// refresh token까지 무효해진 경우. 앱이 할 수 있는 일이 없고 재로그인이 필요하다.
    @Test func invalidGrantIsReported() {
        let data = Data(#"{"error":"invalid_grant"}"#.utf8)

        #expect(OAuthTokenRefresher.interpret(status: 400, data: data) == .invalidGrant)
    }

    @Test func serverErrorIsTransient() {
        #expect(OAuthTokenRefresher.interpret(status: 500, data: Data()) == .failed)
    }

    @Test func malformedSuccessBodyIsTransient() {
        #expect(OAuthTokenRefresher.interpret(status: 200, data: Data("garbage".utf8)) == .failed)
    }
}
