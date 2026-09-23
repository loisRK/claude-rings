import Foundation

public protocol CredentialWriting: Sendable {
    /// 갱신한 자격증명 JSON을 Keychain에 되쓴다. 성공 여부를 돌려준다.
    func write(_ raw: Data, for account: Account) -> Bool
}

/// Claude Code와 같은 방식(`/usr/bin/security`)으로 Keychain 항목을 갱신한다. 항목을 만든
/// 주체가 `security`라서, 같은 도구로 쓰면 허용 창이 뜨지 않고 ACL도 그대로 유지된다.
public struct KeychainCredentialWriter: CredentialWriting {
    /// 값을 `security`에 넘기는 방법. 안전한 순서대로 나열돼 있고, 실제로 값이 왕복하는지
    /// 확인한 뒤 골라 쓴다(`resolveTransport`).
    public enum WriteTransport: Equatable, Sendable, CaseIterable {
        /// `-w`를 마지막 옵션으로 두면 값을 프롬프트로 받는다. 인자에 남지 않아 가장 안전하다.
        case stdin
        /// 확인 입력까지 요구하는 경우를 위해 같은 값을 두 번 보낸다.
        case stdinTwice
        /// 마지막 수단. Claude Code와 같지만 값이 잠깐 `ps`에 보인다.
        case argument
    }

    /// 쓰기가 실제로 되는지 확인할 때 쓰는 일회용 항목의 서비스명.
    public static let probeService = "claude-rings-write-probe"

    private let runner: any CommandRunner
    private let userName: String
    private let transport: WriteTransport

    public init(
        runner: any CommandRunner = ProcessRunner(), userName: String = NSUserName(),
        transport: WriteTransport = .stdin
    ) {
        self.runner = runner
        self.userName = userName
        self.transport = transport
    }

    /// 같은 설정에 전달 방식만 바꾼 사본.
    public func using(_ transport: WriteTransport) -> KeychainCredentialWriter {
        KeychainCredentialWriter(runner: runner, userName: userName, transport: transport)
    }

    public func write(_ raw: Data, for account: Account) -> Bool {
        let service = KeychainService.serviceName(forConfigDir: account.configDir)
        return add(raw, service: service, transport: transport).status == 0
    }

    private func add(_ value: Data, service: String, transport: WriteTransport)
        -> (status: Int32, output: Data)
    {
        var arguments = ["add-generic-password", "-U", "-a", userName, "-s", service, "-w"]
        var input: Data?
        switch transport {
        case .stdin:
            input = value
        case .stdinTwice:
            input = value + Data("\n".utf8) + value + Data("\n".utf8)
        case .argument:
            arguments.append(String(decoding: value, as: UTF8.self))
        }
        return runner.run("/usr/bin/security", arguments, input: input)
    }

    /// 프로브 결과. 실패 지점을 구분해 둬야 무엇을 고쳐야 할지 알 수 있다.
    public enum WriteProbe: Equatable, Sendable {
        case ok
        case writeFailed(status: Int32)
        case readFailed(status: Int32)
        /// 쓰기·읽기는 됐는데 값이 다른 경우. 값 전달 경로가 잘못된 것이다.
        case valueMismatch
    }

    /// GUI 앱에는 제어 터미널이 없어 `security`가 값을 어떻게 받아들이는지 미리 알 수 없다.
    /// 실제 자격증명을 건드리기 전에 일회용 항목으로 쓰기·되읽기를 확인하고 지운다.
    public func probeWritable(probeValue: String = UUID().uuidString) -> WriteProbe {
        defer { deleteProbeItem() }

        let written = add(Data(probeValue.utf8), service: Self.probeService, transport: transport)
        guard written.status == 0 else { return .writeFailed(status: written.status) }

        let read = runner.run(
            "/usr/bin/security", ["find-generic-password", "-s", Self.probeService, "-w"])
        guard read.status == 0 else { return .readFailed(status: read.status) }

        let readBack = String(data: read.output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return readBack == probeValue ? .ok : .valueMismatch
    }

    /// 값이 실제로 왕복하는 첫 전달 방식을 고른다. 전부 실패하면 nil이고, 이때는 갱신 기능을
    /// 켜지 않는다. 쓰기가 조용히 값을 잃어버리는 환경이 실제로 있으므로(GUI 앱의 stdin),
    /// 확인 없이 실제 자격증명에 쓰지 않는다.
    public func resolveTransport(probeValue: String = UUID().uuidString) -> WriteTransport? {
        WriteTransport.allCases.first { using($0).probeWritable(probeValue: probeValue) == .ok }
    }

    public func verifyWritable(probeValue: String = UUID().uuidString) -> Bool {
        probeWritable(probeValue: probeValue) == .ok
    }

    private func deleteProbeItem() {
        _ = runner.run(
            "/usr/bin/security",
            ["delete-generic-password", "-a", userName, "-s", Self.probeService])
    }
}
