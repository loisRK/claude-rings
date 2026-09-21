import Foundation
import Testing
@testable import ClaudeRingsCore

struct AccountStoreTests {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "claude-rings-tests-\(UUID().uuidString)")
    var fileURL: URL { dir.appending(path: "accounts.json") }

    @Test func missingFileWritesAndReturnsDefault() throws {
        let config = AccountStore(fileURL: fileURL).load()

        #expect(config == .default)
        #expect(config.accounts == [Account(name: "main", configDir: "~/.claude")])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func readsCustomAccountsAndDefaultsInterval() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"accounts":[{"name":"main","configDir":"~/.claude"},{"name":"work","configDir":"~/.claude/work"}]}"#
        try Data(json.utf8).write(to: fileURL)

        let config = AccountStore(fileURL: fileURL).load()

        #expect(config.accounts.map(\.name) == ["main", "work"])
        #expect(config.pollIntervalSeconds == 180)
    }

    @Test func corruptFileFallsBackWithoutOverwriting() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: fileURL)

        #expect(AccountStore(fileURL: fileURL).load() == .default)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "{not json")
    }

    @Test func emptyAccountListFallsBackToDefault() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"accounts":[]}"#.utf8).write(to: fileURL)

        #expect(AccountStore(fileURL: fileURL).load() == .default)
    }

    @Test func duplicateAccountNamesKeepFirstOccurrence() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"""
        {"accounts":[
            {"name":"work","configDir":"~/.claude/work"},
            {"name":"main","configDir":"~/.claude"},
            {"name":"work","configDir":"~/.claude/work2"}
        ]}
        """#
        try Data(json.utf8).write(to: fileURL)

        let config = AccountStore(fileURL: fileURL).load()

        #expect(config.accounts == [
            Account(name: "work", configDir: "~/.claude/work"),
            Account(name: "main", configDir: "~/.claude"),
        ])
    }
}
