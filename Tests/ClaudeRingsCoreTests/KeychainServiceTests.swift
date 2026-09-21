import Testing
@testable import ClaudeRingsCore

struct KeychainServiceTests {
    let home = "/Users/alice"

    @Test func defaultDirUsesBaseName() {
        #expect(KeychainService.serviceName(forConfigDir: "~/.claude", home: home) == "Claude Code-credentials")
        #expect(KeychainService.serviceName(forConfigDir: "/Users/alice/.claude/", home: home) == "Claude Code-credentials")
    }

    @Test func customDirUsesHashSuffix() {
        #expect(KeychainService.serviceName(forConfigDir: "~/.claude/work", home: home)
            == "Claude Code-credentials-4163034c")
    }

    @Test func trailingSlashIsIgnored() {
        #expect(KeychainService.serviceName(forConfigDir: "/Users/alice/.claude/work/", home: home)
            == "Claude Code-credentials-4163034c")
    }

    @Test func normalizeExpandsTildeAndTrimsSlash() {
        #expect(KeychainService.normalize("~", home: home) == "/Users/alice")
        #expect(KeychainService.normalize("~/x/", home: home) == "/Users/alice/x")
        #expect(KeychainService.normalize("/", home: home) == "/")
    }
}
