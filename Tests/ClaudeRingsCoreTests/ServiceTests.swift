import Foundation
import Testing

@testable import ClaudeRingsCore

struct ServiceTests {
    @Test func accountDefaultsToClaudeWhenServiceKeyIsAbsent() throws {
        let json = #"{"name":"main","configDir":"~/.claude"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))

        #expect(account.service == .claude)
    }

    @Test func accountDecodesExplicitServiceValue() throws {
        let json = #"{"name":"main","configDir":"~/.claude","service":"codex"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))

        #expect(account.service == ServiceID(rawValue: "codex"))
    }

    @Test func accountEncodesServiceExplicitly() throws {
        let account = Account(name: "main", configDir: "~/.claude")
        let data = try JSONEncoder().encode(account)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["service"] as? String == "claude")
    }

    @Test func registryReturnsPollerOnlyForRegisteredServices() {
        let registry = ServiceRegistry.claudeOnly()

        #expect(registry.isSupported(.claude))
        #expect(registry.poller(for: .claude) != nil)
        #expect(registry.isSupported(ServiceID(rawValue: "codex")) == false)
        #expect(registry.poller(for: ServiceID(rawValue: "codex")) == nil)
    }
}
