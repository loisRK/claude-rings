import Foundation
import Testing
@testable import ClaudeRingsCore

struct CredentialJSONTests {
    /// Claude Code가 저장하는 실제 모양. 앱이 모르는 필드가 섞여 있어도 잃으면 안 된다.
    let raw = Data(#"{"claudeAiOauth":{"accessToken":"old","refreshToken":"r-old","expiresAt":1000,"refreshTokenExpiresAt":5000,"scopes":["a","b"],"subscriptionType":"pro","rateLimitTier":"default_claude_ai"},"futureField":1}"#.utf8)

    @Test func updatesTokensAndKeepsUnknownFields() throws {
        let tokens = RefreshedTokens(
            accessToken: "new", refreshToken: "r-new", expiresIn: 60, refreshTokenExpiresIn: 120)

        let updated = try #require(CredentialJSON.applying(tokens, to: raw, now: Date(timeIntervalSince1970: 10)))

        let object = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let oauth = try #require(object["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new")
        #expect(oauth["refreshToken"] as? String == "r-new")
        #expect(oauth["expiresAt"] as? Double == 70_000)
        #expect(oauth["refreshTokenExpiresAt"] as? Double == 130_000)
        #expect(oauth["subscriptionType"] as? String == "pro")
        #expect(oauth["scopes"] as? [String] == ["a", "b"])
        #expect(object["futureField"] as? Int == 1)
    }

    @Test func keepsStoredRefreshTokenWhenResponseOmitsIt() throws {
        let tokens = RefreshedTokens(
            accessToken: "new", refreshToken: nil, expiresIn: 60, refreshTokenExpiresIn: nil)

        let updated = try #require(CredentialJSON.applying(tokens, to: raw, now: Date(timeIntervalSince1970: 10)))

        let oauth = try #require(
            (JSONSerialization.jsonObject(with: updated) as? [String: Any])?["claudeAiOauth"] as? [String: Any])
        #expect(oauth["refreshToken"] as? String == "r-old")
        #expect(oauth["refreshTokenExpiresAt"] as? Double == 5000)
    }

    @Test func malformedJSONYieldsNothing() {
        let tokens = RefreshedTokens(
            accessToken: "a", refreshToken: nil, expiresIn: 1, refreshTokenExpiresIn: nil)

        #expect(CredentialJSON.applying(tokens, to: Data("garbage".utf8), now: .now) == nil)
    }
}
