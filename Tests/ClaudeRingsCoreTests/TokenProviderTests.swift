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

        #expect(try provider.accessToken(for: account) == "tok-123")
    }

    @Test func missingItemThrowsNotFound() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 44, output: ""))
        #expect(throws: TokenError.notFound) { try provider.accessToken(for: account) }
    }

    @Test func otherFailureThrowsAccessDenied() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 51, output: ""))
        #expect(throws: TokenError.accessDenied) { try provider.accessToken(for: account) }
    }

    @Test func unparsableOutputThrowsMalformed() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 0, output: "garbage"))
        #expect(throws: TokenError.malformed) { try provider.accessToken(for: account) }
    }
}
