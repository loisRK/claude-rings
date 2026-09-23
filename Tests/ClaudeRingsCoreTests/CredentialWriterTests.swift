import Foundation
import Testing
@testable import ClaudeRingsCore

final class RecordingRunner: CommandRunner, @unchecked Sendable {
    struct Invocation: Equatable {
        let arguments: [String]
        let input: Data?
    }

    private let lock = NSLock()
    private(set) var invocations: [Invocation] = []
    private var results: [(Int32, Data)]

    init(results: [(Int32, Data)]) { self.results = results }

    func run(_ executable: String, _ arguments: [String], input: Data?) -> (status: Int32, output: Data) {
        lock.withLock {
            invocations.append(Invocation(arguments: arguments, input: input))
            return results.count > 1 ? results.removeFirst() : results[0]
        }
    }
}

struct CredentialWriterTests {
    let account = Account(name: "work", configDir: "~/.claude/work")
    let raw = Data(#"{"claudeAiOauth":{"accessToken":"secret-token"}}"#.utf8)
    var service: String { KeychainService.serviceName(forConfigDir: account.configDir) }

    private func ok(_ value: String) -> (Int32, Data) { (0, Data((value + "\n").utf8)) }

    @Test func stdinTransportKeepsTokenOutOfArguments() {
        let runner = RecordingRunner(results: [(0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice", transport: .stdin)

        #expect(writer.write(raw, for: account))

        let invocation = runner.invocations[0]
        #expect(invocation.arguments == ["add-generic-password", "-U", "-a", "alice", "-s", service, "-w"])
        #expect(invocation.input == raw)
        #expect(invocation.arguments.allSatisfy { !$0.contains("secret-token") })
    }

    /// 확인 입력까지 요구하는 경우를 위해 같은 값을 두 번 보낸다.
    @Test func stdinTwiceTransportSendsValueTwice() {
        let runner = RecordingRunner(results: [(0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice", transport: .stdinTwice)

        #expect(writer.write(raw, for: account))

        let input = runner.invocations[0].input
        #expect(input == raw + Data("\n".utf8) + raw + Data("\n".utf8))
    }

    /// 마지막 수단. Claude Code와 같은 방식이지만 값이 잠깐 `ps`에 보인다.
    @Test func argumentTransportPassesValueAsArgument() {
        let runner = RecordingRunner(results: [(0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice", transport: .argument)

        #expect(writer.write(raw, for: account))

        let invocation = runner.invocations[0]
        #expect(invocation.input == nil)
        #expect(invocation.arguments.contains(String(decoding: raw, as: UTF8.self)))
    }

    @Test func writeFailsWhenSecurityReturnsNonZero() {
        let writer = KeychainCredentialWriter(
            runner: RecordingRunner(results: [(1, Data())]), userName: "alice", transport: .stdin)

        #expect(writer.write(raw, for: account) == false)
    }

    /// GUI 앱에서는 stdin 경로가 값을 잃어버리는 것이 실측으로 확인됐다(valueMismatch).
    /// 어느 방식이 실제로 왕복하는지 일회용 항목으로 확인한 뒤 그 방식만 쓴다.
    @Test func resolvesToFirstTransportThatRoundTrips() {
        // stdin: 값이 어긋남 → stdinTwice: 왕복 성공
        let runner = RecordingRunner(results: [
            (0, Data()), ok("garbage"), (0, Data()),
            (0, Data()), ok("probe-1"), (0, Data()),
        ])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.resolveTransport(probeValue: "probe-1") == .stdinTwice)
    }

    @Test func fallsBackToArgumentWhenStdinPathsFail() {
        let runner = RecordingRunner(results: [
            (0, Data()), ok("garbage"), (0, Data()),
            (0, Data()), ok("garbage"), (0, Data()),
            (0, Data()), ok("probe-1"), (0, Data()),
        ])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.resolveTransport(probeValue: "probe-1") == .argument)
    }

    @Test func resolvesToNothingWhenEveryTransportFails() {
        let runner = RecordingRunner(results: [(0, Data()), ok("garbage"), (0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.resolveTransport(probeValue: "probe-1") == nil)
        // 어떤 경우에도 일회용 항목은 남기지 않는다.
        #expect(runner.invocations.last?.arguments.first == "delete-generic-password")
    }

    @Test func probeReportsFailedWrite() {
        let runner = RecordingRunner(results: [(1, Data()), (0, Data()), (0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.probeWritable(probeValue: "probe-1") == .writeFailed(status: 1))
    }

    @Test func probeReportsFailedRead() {
        let runner = RecordingRunner(results: [(0, Data()), (44, Data()), (0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.probeWritable(probeValue: "probe-1") == .readFailed(status: 44))
    }
}
