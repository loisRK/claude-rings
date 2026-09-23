import Foundation
import Testing
@testable import ClaudeRingsCore

struct FakeRunner: CommandRunner {
    var status: Int32
    var output: String
    var expectedService: String? = nil

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        if let expectedService {
            guard executable == "/usr/bin/security",
                  arguments == ["find-generic-password", "-s", expectedService, "-w"]
            else { return (44, Data()) }
        }
        return (status, Data(output.utf8))
    }
}

struct TokenProviderTests {
    let account = Account(name: "work", configDir: "~/.claude/work")
    let credentials = #"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r","expiresAt":1}}"# + "\n"

    @Test func returnsAccessTokenForServiceOfAccount() throws {
        let runner = FakeRunner(
            status: 0, output: credentials,
            expectedService: KeychainService.serviceName(forConfigDir: account.configDir))
        let provider = KeychainTokenProvider(runner: runner)

        #expect(try provider.credential(for: account).accessToken == "tok-123")
    }

    @Test func parsesExpiryFromCredentials() throws {
        // Claude Code는 expiresAt을 밀리초 단위 epoch로 저장한다.
        let runner = FakeRunner(
            status: 0, output: #"{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":1790067000000}}"#)
        let provider = KeychainTokenProvider(runner: runner)

        let credential = try provider.credential(for: account)

        #expect(credential.accessToken == "tok-123")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1790067000))
    }

    @Test func credentialWithoutExpiresAtHasNoExpiry() throws {
        let runner = FakeRunner(status: 0, output: #"{"claudeAiOauth":{"accessToken":"tok-123"}}"#)

        #expect(try KeychainTokenProvider(runner: runner).credential(for: account).expiresAt == nil)
    }

    @Test func missingItemThrowsNotFound() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 44, output: ""))
        #expect(throws: TokenError.notFound) { try provider.credential(for: account) }
    }

    @Test func otherFailureThrowsAccessDenied() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 51, output: ""))
        #expect(throws: TokenError.accessDenied) { try provider.credential(for: account) }
    }

    @Test func unparsableOutputThrowsMalformed() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 0, output: "garbage"))
        #expect(throws: TokenError.malformed) { try provider.credential(for: account) }
    }
}
