import Foundation

public enum TokenError: Error, Equatable, Sendable {
    case notFound
    case accessDenied
    case malformed
}

public protocol TokenProvider: Sendable {
    func accessToken(for account: Account) throws(TokenError) -> String
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data)
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, Data())
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}

/// Claude Code가 저장한 Keychain 항목을 `security` CLI로 읽는다. 쓰기는 하지 않는다.
public struct KeychainTokenProvider: TokenProvider {
    /// `security`가 항목을 찾지 못했을 때의 종료 코드(errSecItemNotFound)
    static let itemNotFoundStatus: Int32 = 44

    private let runner: any CommandRunner

    public init(runner: any CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func accessToken(for account: Account) throws(TokenError) -> String {
        let service = KeychainService.serviceName(forConfigDir: account.configDir)
        let result = runner.run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
        switch result.status {
        case 0: break
        case Self.itemNotFoundStatus: throw .notFound
        default: throw .accessDenied
        }

        struct Credentials: Decodable {
            struct OAuth: Decodable { let accessToken: String }
            let claudeAiOauth: OAuth
        }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: result.output) else {
            throw .malformed
        }
        return credentials.claudeAiOauth.accessToken
    }
}
