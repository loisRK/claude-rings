import Foundation

public enum TokenError: Error, Equatable, Sendable {
    case notFound
    case accessDenied
    case malformed
}

/// Keychain에서 읽은 자격증명. 토큰 값과, Claude Code가 함께 저장한 만료 시각을 담는다.
public struct Credential: Equatable, Sendable {
    public let accessToken: String
    /// 만료 시각. 자격증명에 값이 없으면 nil이며, 이때는 만료 여부를 판단하지 않는다.
    public let expiresAt: Date?
    /// 토큰 갱신에 쓰는 값. 없으면 갱신할 수 없다.
    public let refreshToken: String?
    /// 갱신 요청에 그대로 실어 보내야 하는 권한 목록.
    public let scopes: [String]
    /// Keychain에 저장돼 있던 JSON 원본. 갱신 결과를 되쓸 때 모르는 필드를 잃지 않으려고 보관한다.
    public let raw: Data

    public init(
        accessToken: String, expiresAt: Date? = nil, refreshToken: String? = nil,
        scopes: [String] = [], raw: Data = Data()
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.scopes = scopes
        self.raw = raw
    }
}

public protocol TokenProvider: Sendable {
    func credential(for account: Account) throws(TokenError) -> Credential
}

public protocol CommandRunner: Sendable {
    /// `input`이 있으면 자식 프로세스의 stdin으로 넘긴다. 토큰처럼 인자로 노출되면 안 되는
    /// 값을 전달할 때 쓴다.
    func run(_ executable: String, _ arguments: [String], input: Data?) -> (status: Int32, output: Data)
}

extension CommandRunner {
    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        run(executable, arguments, input: nil)
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], input: Data?)
        -> (status: Int32, output: Data)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe {
            process.standardInput = inputPipe
        }
        do {
            try process.run()
        } catch {
            return (-1, Data())
        }
        if let inputPipe, let input {
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
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

    public func credential(for account: Account) throws(TokenError) -> Credential {
        let service = KeychainService.serviceName(forConfigDir: account.configDir)
        let result = runner.run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
        switch result.status {
        case 0: break
        case Self.itemNotFoundStatus: throw .notFound
        default: throw .accessDenied
        }

        struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                /// 밀리초 단위 epoch. 예전 자격증명에는 없을 수 있어 옵셔널로 읽는다.
                let expiresAt: Double?
                let refreshToken: String?
                let scopes: [String]?
            }
            let claudeAiOauth: OAuth
        }
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: result.output) else {
            throw .malformed
        }
        let oauth = credentials.claudeAiOauth
        return Credential(
            accessToken: oauth.accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            refreshToken: oauth.refreshToken,
            scopes: oauth.scopes ?? [],
            raw: result.output)
    }
}
