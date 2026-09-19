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
        (429, .rateLimited),
        (500, .failed),
        (0, .failed),
    ])
    func mapsStatusCodes(status: Int, expected: FetchResult) {
        #expect(UsageClient.interpret(status: status, data: Data()) == expected)
    }
}
