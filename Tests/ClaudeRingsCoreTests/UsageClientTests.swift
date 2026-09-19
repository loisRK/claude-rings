import Foundation
import Testing
@testable import ClaudeRingsCore

struct UsageClientTests {
    @Test func requestHasRequiredHeaders() {
        let request = UsageClient.makeRequest(token: "tok")

        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.timeoutInterval == 10)
    }

    @Test func okWithValidBody() {
        let result = UsageClient.interpret(status: 200, data: Data(sampleUsageJSON.utf8))
        guard case .ok(let usage) = result else {
            Issue.record("expected .ok, got \(result)")
            return
        }
        #expect(usage.session?.remainingPercent == 76)
    }

    @Test func okWithUnparsableBodyIsFailed() {
        #expect(UsageClient.interpret(status: 200, data: Data("garbage".utf8)) == .failed)
    }

    @Test(arguments: [
        (401, FetchResult.unauthorized),
        (403, .unauthorized),
        (429, .rateLimited(retryAfter: nil)),
        (500, .failed),
        (0, .failed),
    ])
    func mapsStatusCodes(status: Int, expected: FetchResult) {
        #expect(UsageClient.interpret(status: status, data: Data()) == expected)
    }

    @Test func rateLimitedWithIntegerRetryAfterParsesSeconds() {
        let result = UsageClient.interpret(status: 429, data: Data(), retryAfter: "3544")
        #expect(result == .rateLimited(retryAfter: 3544))
    }

    @Test func rateLimitedWithoutRetryAfterHeaderIsNil() {
        let result = UsageClient.interpret(status: 429, data: Data(), retryAfter: nil)
        #expect(result == .rateLimited(retryAfter: nil))
    }

    @Test func rateLimitedWithHTTPDateRetryAfterIsUnparsedAsNil() {
        let result = UsageClient.interpret(status: 429, data: Data(), retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT")
        #expect(result == .rateLimited(retryAfter: nil))
    }

    @Test func rateLimitedWithFractionalRetryAfterIsNil() {
        let result = UsageClient.interpret(status: 429, data: Data(), retryAfter: "3.5")
        #expect(result == .rateLimited(retryAfter: nil))
    }
}
