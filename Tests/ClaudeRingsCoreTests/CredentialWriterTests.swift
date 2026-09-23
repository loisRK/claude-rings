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

    @Test func writeSendsJSONThroughStdinNeverAsArgument() {
        let runner = RecordingRunner(results: [(0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.write(raw, for: account))

        let invocation = runner.invocations[0]
        #expect(invocation.arguments == ["add-generic-password", "-U", "-a", "alice", "-s", service, "-w"])
        #expect(invocation.input == raw)
        // 값을 인자로 넘기면 ps로 토큰이 새 나간다. -w는 반드시 마지막 인자여야 한다.
        #expect(invocation.arguments.last == "-w")
        #expect(invocation.arguments.allSatisfy { !$0.contains("secret-token") })
    }

    @Test func writeFailsWhenSecurityReturnsNonZero() {
        let writer = KeychainCredentialWriter(runner: RecordingRunner(results: [(1, Data())]), userName: "alice")

        #expect(writer.write(raw, for: account) == false)
    }

    /// GUI 앱에는 제어 터미널이 없어 `security`의 프롬프트가 stdin을 읽는지 미리 알 수 없다.
    /// 실제 자격증명을 건드리기 전에 일회용 항목으로 쓰기·되읽기·삭제를 확인한다.
    @Test func probeConfirmsWriteWhenValueReadsBack() {
        let runner = RecordingRunner(results: [(0, Data()), (0, Data("probe-1\n".utf8)), (0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.verifyWritable(probeValue: "probe-1"))

        #expect(runner.invocations.count == 3)
        #expect(runner.invocations[0].arguments.contains(KeychainCredentialWriter.probeService))
        #expect(runner.invocations[1].arguments.first == "find-generic-password")
        #expect(runner.invocations[2].arguments.first == "delete-generic-password")
    }

    @Test func probeFailsWhenValueDoesNotReadBack() {
        let runner = RecordingRunner(results: [(0, Data()), (0, Data("other\n".utf8)), (0, Data())])
        let writer = KeychainCredentialWriter(runner: runner, userName: "alice")

        #expect(writer.verifyWritable(probeValue: "probe-1") == false)
        // 실패해도 일회용 항목은 반드시 지운다.
        #expect(runner.invocations.last?.arguments.first == "delete-generic-password")
    }
}
