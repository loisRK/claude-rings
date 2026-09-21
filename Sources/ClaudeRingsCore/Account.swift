import Foundation

public struct Account: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var name: String
    public var configDir: String
    public var service: ServiceID
    public var id: String { name }

    public init(name: String, configDir: String, service: ServiceID = .claude) {
        self.name = name
        self.configDir = configDir
        self.service = service
    }

    /// 기존 `accounts.json`(=`service` 필드가 없는 파일)도 계속 읽히도록, 없으면 `.claude`로 채운다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        configDir = try container.decode(String.self, forKey: .configDir)
        service = try container.decodeIfPresent(ServiceID.self, forKey: .service) ?? .claude
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var accounts: [Account]
    public var pollIntervalSeconds: Int

    public static let defaultPollInterval = 180

    public static let `default` = AppConfig(
        accounts: [Account(name: "main", configDir: "~/.claude")],
        pollIntervalSeconds: defaultPollInterval
    )

    public init(accounts: [Account], pollIntervalSeconds: Int) {
        self.accounts = accounts
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([Account].self, forKey: .accounts)
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds)
            ?? Self.defaultPollInterval
    }
}

public struct AccountStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AccountStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/claude-rings/accounts.json")
    }

    /// 파일이 없으면 기본값을 기록해 반환한다.
    /// 파일이 손상됐거나 계정이 비어 있으면 파일은 건드리지 않고 기본값을 반환한다.
    public func load() -> AppConfig {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try? fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? encoder.encode(AppConfig.default).write(to: fileURL)
            return .default
        }
        guard let data = try? Data(contentsOf: fileURL),
              var config = try? JSONDecoder().decode(AppConfig.self, from: data),
              !config.accounts.isEmpty
        else { return .default }
        config.accounts = Self.dedupingByName(config.accounts)
        return config
    }

    /// 이름이 같은 계정이 여러 개면 처음 나온 것만 남긴다.
    private static func dedupingByName(_ accounts: [Account]) -> [Account] {
        var seen = Set<String>()
        return accounts.filter { seen.insert($0.name).inserted }
    }
}
