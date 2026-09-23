import Foundation

public protocol CredentialWriting: Sendable {
    /// 갱신한 자격증명 JSON을 Keychain에 되쓴다. 성공 여부를 돌려준다.
    func write(_ raw: Data, for account: Account) -> Bool
}

/// Claude Code와 같은 방식(`/usr/bin/security`)으로 Keychain 항목을 갱신한다. 항목을 만든
/// 주체가 `security`라서, 같은 도구로 쓰면 허용 창이 뜨지 않고 ACL도 그대로 유지된다.
public struct KeychainCredentialWriter: CredentialWriting {
    /// 쓰기가 실제로 되는지 확인할 때 쓰는 일회용 항목의 서비스명.
    public static let probeService = "claude-rings-write-probe"

    private let runner: any CommandRunner
    private let userName: String

    public init(runner: any CommandRunner = ProcessRunner(), userName: String = NSUserName()) {
        self.runner = runner
        self.userName = userName
    }

    /// `security`는 값을 받는 옵션을 마지막에 두면 프롬프트로 받는다. 값을 인자로 주면
    /// `ps`에 토큰이 그대로 노출되므로 반드시 stdin으로 넘긴다.
    static func addArguments(service: String, account: String) -> [String] {
        ["add-generic-password", "-U", "-a", account, "-s", service, "-w"]
    }

    public func write(_ raw: Data, for account: Account) -> Bool {
        let service = KeychainService.serviceName(forConfigDir: account.configDir)
        return runner.run(
            "/usr/bin/security", Self.addArguments(service: service, account: userName), input: raw
        ).status == 0
    }

    /// GUI 앱에는 제어 터미널이 없어 `security`의 프롬프트가 stdin에서 읽히는지 미리 알 수
    /// 없다. 실제 자격증명을 건드리기 전에 일회용 항목으로 쓰기·되읽기를 확인하고 지운다.
    public func verifyWritable(probeValue: String = UUID().uuidString) -> Bool {
        defer {
            _ = runner.run(
                "/usr/bin/security",
                ["delete-generic-password", "-a", userName, "-s", Self.probeService])
        }
        let written = runner.run(
            "/usr/bin/security",
            Self.addArguments(service: Self.probeService, account: userName),
            input: Data(probeValue.utf8))
        guard written.status == 0 else { return false }

        let read = runner.run(
            "/usr/bin/security", ["find-generic-password", "-s", Self.probeService, "-w"])
        guard read.status == 0 else { return false }
        return String(data: read.output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == probeValue
    }
}
