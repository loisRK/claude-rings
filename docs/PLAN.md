# claude-rings 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 여러 Claude Code 계정(config 디렉터리별)의 Session·Weekly 잔여율을, 항상 위에 떠 있는 Liquid Glass 링 위젯으로 보여주는 macOS 앱을 만든다.

**Architecture:** UI와 무관한 로직은 `ClaudeRingsCore` 라이브러리에 두고 Swift Testing으로 TDD한다. 앱 실행 파일 `ClaudeRings`는 AppKit `NSPanel`과 SwiftUI 뷰로 Core를 조립한다. 셸 함수가 세션 파일을 등록해 앱을 띄우고, 앱은 등록된 세션이 모두 끝나면 스스로 종료한다.

**Tech Stack:** Swift 6 (Swift Package Manager), SwiftUI Liquid Glass(`glassEffect`), AppKit(`NSPanel`), Swift Testing, `/usr/bin/security`, URLSession, zsh

**Spec:** [docs/DESIGN.md](DESIGN.md)

## Global Constraints

- 최소 OS: macOS 26 (`platforms: [.macOS(.v26)]`)
- 외부 의존성 없음 (Apple 프레임워크만 사용)
- Keychain은 **읽기 전용**. 토큰 갱신·쓰기 금지
- 토큰 값은 로그·출력·오류 메시지·테스트 픽스처 어디에도 남기지 않음
- 저장소는 공개용이므로 개인 식별 정보(실제 사용자명, 실제 계정 alias, 실제 이메일, 실제 Keychain 해시)를 코드·문서·커밋 메시지에 넣지 않음. 예시는 `/Users/alice`, `~/.claude/work`, `4163034c`를 사용
- 사용량 API: `GET https://api.anthropic.com/api/oauth/usage`, 헤더 `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`
- 기본 조회 간격 180초(최소 30초), 백오프 2배씩 최대 900초, 요청 타임아웃 10초
- 색상 단계(남은 %): 50 이상 초록, 20 이상 초록 미만 노랑, 20 미만 빨강, 값 없음 회색
- 세션 디렉터리: `~/.claude-rings/sessions/<셸 PID>` (내용: config 디렉터리 경로). 세션이 0개인 상태가 10초 지속되면 종료
- 설정 파일: `~/.config/claude-rings/accounts.json`
- 커밋 메시지는 한국어, conventional commit 접두사(`feat:`, `test:`, `docs:`, `chore:`) 사용

## 파일 구조

| 파일 | 책임 |
|---|---|
| `Package.swift` | 타깃 3개: `ClaudeRingsCore`(라이브러리), `ClaudeRings`(실행 파일), `ClaudeRingsCoreTests` |
| `Sources/ClaudeRingsCore/Account.swift` | `Account`, `AppConfig`, `AccountStore` |
| `Sources/ClaudeRingsCore/KeychainService.swift` | 경로 정규화, Keychain 서비스명 계산 |
| `Sources/ClaudeRingsCore/TokenProvider.swift` | `TokenProvider` 프로토콜, `security` CLI 구현 |
| `Sources/ClaudeRingsCore/Usage.swift` | `Usage`, `UsageWindow`, `UsageParser` |
| `Sources/ClaudeRingsCore/UsageClient.swift` | `FetchResult`, `UsageFetching`, `UsageClient` |
| `Sources/ClaudeRingsCore/UsageState.swift` | `AccountStatus`, `RingLevel`, `StatusReducer`, `Backoff`, `ResetFormatter` |
| `Sources/ClaudeRingsCore/AccountPoller.swift` | 토큰 → 조회 → 401 재시도 → 상태 결정 |
| `Sources/ClaudeRingsCore/SessionWatcher.swift` | 세션 PID 추적, 활성 계정, 종료 판단 |
| `Sources/ClaudeRings/main.swift` | `NSApplication` 부트스트랩 |
| `Sources/ClaudeRings/AppDelegate.swift` | 구성 요소 조립, 세션 타이머 |
| `Sources/ClaudeRings/UsageViewModel.swift` | 계정별 조회 루프, 화면 상태 |
| `Sources/ClaudeRings/RingsPanel.swift` | 투명·항상 위 `NSPanel`, 위치 저장 |
| `Sources/ClaudeRings/RingsView.swift` | Liquid Glass 버블, 이중 링 |
| `Support/Info.plist` | `.app` 번들 메타데이터(`LSUIElement`) |
| `scripts/probe-usage.sh` | API 수동 확인 |
| `scripts/build-app.sh` | `.app` 빌드·설치 |
| `scripts/claude-rings.zsh` | 셸 함수 |

---

### Task 1: 사용량 API와 Keychain 읽기 방식 검증 (게이트)

설계 전체가 비공식 API와 `security` CLI 방식에 기대고 있다. 코드를 쓰기 전에 실제 동작을 확인한다. **예상과 다르면 여기서 멈추고 설계(`docs/DESIGN.md`)와 Task 4를 먼저 고친다.**

**Files:**
- Create: `scripts/probe-usage.sh`

**Interfaces:**
- Consumes: 없음
- Produces: 실제 응답 스키마 확인 결과(Task 4 파서가 기대하는 키: `five_hour.utilization`, `five_hour.resets_at`, `seven_day.utilization`, `seven_day.resets_at`)

- [ ] **Step 1: 확인 스크립트 작성**

```bash
#!/usr/bin/env bash
# 사용량 API 응답을 확인한다. 토큰은 출력하지 않는다.
# 사용법: scripts/probe-usage.sh [config-dir]   (기본값: ~/.claude)
set -euo pipefail

cfg="${1:-$HOME/.claude}"
cfg="${cfg/#\~/$HOME}"
cfg="${cfg%/}"

if [[ "$cfg" == "$HOME/.claude" ]]; then
  svc="Claude Code-credentials"
else
  svc="Claude Code-credentials-$(printf '%s' "$cfg" | shasum -a 256 | cut -c1-8)"
fi
echo "keychain service: $svc" >&2

token="$(security find-generic-password -s "$svc" -w \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')"

# 토큰이 프로세스 인자에 노출되지 않도록 헤더를 stdin으로 전달한다.
printf 'Authorization: Bearer %s\n' "$token" | curl -sS -w '\nHTTP %{http_code}\n' \
  -H @- \
  -H 'anthropic-beta: oauth-2025-04-20' \
  -H 'Accept: application/json' \
  https://api.anthropic.com/api/oauth/usage
```

- [ ] **Step 2: 실행 권한 부여 후 기본 계정으로 실행**

Run: `chmod +x scripts/probe-usage.sh && scripts/probe-usage.sh`
Expected:
- macOS Keychain 허용 창이 **뜨지 않음** (뜨면 기록하고 "허용"을 선택한 뒤, 설계 §2 "Keychain 읽기 방식" 문구를 실제 동작에 맞게 수정)
- 마지막 줄이 `HTTP 200`
- 본문이 `{"five_hour":{"utilization":<숫자>,"resets_at":"<ISO8601>"},"seven_day":{...},...}` 형태

- [ ] **Step 3: 두 번째 계정으로 실행**

Run: `scripts/probe-usage.sh ~/.claude/<두 번째 계정 디렉터리>`
Expected: 서비스명이 `Claude Code-credentials-<8자리>`로 출력되고, Step 2와 같은 형태의 `HTTP 200` 응답

- [ ] **Step 4: 스키마 대조**

응답을 아래 기대 스키마와 비교한다.

```json
{
  "five_hour": { "utilization": 24.0, "resets_at": "2026-09-18T10:00:00.123456+00:00" },
  "seven_day": { "utilization": 20.0, "resets_at": "2026-09-20T03:00:00+00:00" }
}
```

- `utilization`이 0~100 범위의 **사용률**인지 확인한다(잔여율이 아님). 기존 모니터링 앱에 보이는 "N% left"와 `100 - utilization`이 일치하면 맞다.
- 키 이름이나 의미가 다르면 Task 4의 `UsageParser`와 테스트의 키, 설계 §2·§4를 먼저 수정한다.
- `HTTP 401`이면 해당 계정으로 Claude Code를 한 번 실행해 토큰을 갱신한 뒤 다시 시도한다. 그래도 401이면 헤더 조합을 조사하기 전까지 진행하지 않는다.

- [ ] **Step 5: 커밋**

응답 본문은 커밋하지 않는다(스크립트만 커밋).

```bash
git add scripts/probe-usage.sh
git commit -m "chore: 사용량 API 확인 스크립트 추가"
```

---

### Task 2: 패키지 뼈대와 AccountStore

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeRingsCore/Account.swift`
- Create: `Sources/ClaudeRings/main.swift` (임시: 빌드용 최소 코드, Task 8에서 교체)
- Test: `Tests/ClaudeRingsCoreTests/AccountStoreTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `public struct Account: Codable, Equatable, Hashable, Identifiable, Sendable { var name: String; var configDir: String; var id: String }`
  - `public struct AppConfig: Codable, Equatable, Sendable { var accounts: [Account]; var pollIntervalSeconds: Int; static let default }`
  - `public struct AccountStore: Sendable { let fileURL: URL; init(fileURL: URL = AccountStore.defaultFileURL); static var defaultFileURL: URL; func load() -> AppConfig }`

- [ ] **Step 1: `Package.swift` 작성**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeRings",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ClaudeRingsCore"),
        .executableTarget(name: "ClaudeRings", dependencies: ["ClaudeRingsCore"]),
        .testTarget(name: "ClaudeRingsCoreTests", dependencies: ["ClaudeRingsCore"]),
    ]
)
```

- [ ] **Step 2: 임시 `Sources/ClaudeRings/main.swift` 작성**

```swift
import ClaudeRingsCore

print(AccountStore().load().accounts.map(\.name))
```

- [ ] **Step 3: 실패하는 테스트 작성** — `Tests/ClaudeRingsCoreTests/AccountStoreTests.swift`

```swift
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
}
```

- [ ] **Step 4: 테스트 실패 확인**

Run: `swift test --filter AccountStoreTests`
Expected: 컴파일 실패 — `cannot find 'AccountStore' in scope`

- [ ] **Step 5: 구현** — `Sources/ClaudeRingsCore/Account.swift`

```swift
import Foundation

public struct Account: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var name: String
    public var configDir: String
    public var id: String { name }

    public init(name: String, configDir: String) {
        self.name = name
        self.configDir = configDir
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
              let config = try? JSONDecoder().decode(AppConfig.self, from: data),
              !config.accounts.isEmpty
        else { return .default }
        return config
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter AccountStoreTests`
Expected: `Test run with 4 tests ... passed`

- [ ] **Step 7: 커밋**

```bash
git add Package.swift Sources Tests
git commit -m "feat: 패키지 뼈대와 계정 설정 로더 추가"
```

---

### Task 3: Keychain 서비스명과 토큰 읽기

**Files:**
- Create: `Sources/ClaudeRingsCore/KeychainService.swift`
- Create: `Sources/ClaudeRingsCore/TokenProvider.swift`
- Test: `Tests/ClaudeRingsCoreTests/KeychainServiceTests.swift`
- Test: `Tests/ClaudeRingsCoreTests/TokenProviderTests.swift`

**Interfaces:**
- Consumes: `Account` (Task 2)
- Produces:
  - `public enum KeychainService { static let baseName: String; static func normalize(_ path: String, home: String = NSHomeDirectory()) -> String; static func serviceName(forConfigDir path: String, home: String = NSHomeDirectory()) -> String }`
  - `public enum TokenError: Error, Equatable, Sendable { case notFound, accessDenied, malformed }`
  - `public protocol TokenProvider: Sendable { func accessToken(for account: Account) throws(TokenError) -> String }`
  - `public protocol CommandRunner: Sendable { func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) }`
  - `public struct ProcessRunner: CommandRunner`
  - `public struct KeychainTokenProvider: TokenProvider { init(runner: any CommandRunner = ProcessRunner()) }`

- [ ] **Step 1: 서비스명 테스트 작성** — `Tests/ClaudeRingsCoreTests/KeychainServiceTests.swift`

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter KeychainServiceTests`
Expected: 컴파일 실패 — `cannot find 'KeychainService' in scope`

- [ ] **Step 3: 구현** — `Sources/ClaudeRingsCore/KeychainService.swift`

```swift
import CryptoKit
import Foundation

public enum KeychainService {
    public static let baseName = "Claude Code-credentials"

    /// `~`를 확장하고 끝의 `/`를 제거한다. Claude Code가 해시하는 경로와 같아야 한다.
    public static func normalize(_ path: String, home: String = NSHomeDirectory()) -> String {
        var result = path
        if result == "~" {
            result = home
        } else if result.hasPrefix("~/") {
            result = home + result.dropFirst()
        }
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// 기본 config(`~/.claude`)는 접미사가 없고, 그 외에는 경로 SHA-256의 앞 8자리를 붙인다.
    public static func serviceName(forConfigDir path: String, home: String = NSHomeDirectory()) -> String {
        let normalized = normalize(path, home: home)
        if normalized == normalize("~/.claude", home: home) {
            return baseName
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(baseName)-\(hex.prefix(8))"
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter KeychainServiceTests`
Expected: 4 tests passed

- [ ] **Step 5: 토큰 읽기 테스트 작성** — `Tests/ClaudeRingsCoreTests/TokenProviderTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

struct FakeRunner: CommandRunner {
    var status: Int32
    var output: String
    var expectedService: String? = nil

    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        if let expectedService {
            guard executable == "/usr/bin/security",
                  arguments == ["find-generic-password", "-s", expectedService, "-w"]
            else { return (44, Data()) }
        }
        return (status, Data(output.utf8))
    }
}

struct TokenProviderTests {
    let account = Account(name: "work", configDir: "~/.claude/work")
    let credentials = #"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r","expiresAt":1}}"# + "\n"

    @Test func returnsAccessTokenForServiceOfAccount() throws {
        let runner = FakeRunner(
            status: 0, output: credentials,
            expectedService: KeychainService.serviceName(forConfigDir: account.configDir))
        let provider = KeychainTokenProvider(runner: runner)

        #expect(try provider.accessToken(for: account) == "tok-123")
    }

    @Test func missingItemThrowsNotFound() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 44, output: ""))
        #expect(throws: TokenError.notFound) { try provider.accessToken(for: account) }
    }

    @Test func otherFailureThrowsAccessDenied() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 51, output: ""))
        #expect(throws: TokenError.accessDenied) { try provider.accessToken(for: account) }
    }

    @Test func unparsableOutputThrowsMalformed() {
        let provider = KeychainTokenProvider(runner: FakeRunner(status: 0, output: "garbage"))
        #expect(throws: TokenError.malformed) { try provider.accessToken(for: account) }
    }
}
```

- [ ] **Step 6: 실패 확인**

Run: `swift test --filter TokenProviderTests`
Expected: 컴파일 실패 — `cannot find type 'CommandRunner' in scope`

- [ ] **Step 7: 구현** — `Sources/ClaudeRingsCore/TokenProvider.swift`

```swift
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
```

- [ ] **Step 8: 통과 확인**

Run: `swift test --filter "KeychainServiceTests|TokenProviderTests"`
Expected: 8 tests passed

- [ ] **Step 9: 커밋**

```bash
git add Sources/ClaudeRingsCore/KeychainService.swift Sources/ClaudeRingsCore/TokenProvider.swift Tests
git commit -m "feat: Keychain 서비스명 계산과 토큰 읽기 추가"
```

---

### Task 4: 사용량 모델, 파서, API 클라이언트

Task 1에서 확인한 스키마가 아래와 다르면 키 이름을 실제에 맞춰 바꾼 뒤 진행한다.

**Files:**
- Create: `Sources/ClaudeRingsCore/Usage.swift`
- Create: `Sources/ClaudeRingsCore/UsageClient.swift`
- Test: `Tests/ClaudeRingsCoreTests/UsageTests.swift`
- Test: `Tests/ClaudeRingsCoreTests/UsageClientTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `public struct UsageWindow: Equatable, Sendable { var utilization: Double; var resetsAt: Date?; var remainingPercent: Int }`
  - `public struct Usage: Equatable, Sendable { var session: UsageWindow?; var weekly: UsageWindow? }`
  - `public enum UsageParser { static func parse(_ data: Data) -> Usage? }`
  - `public enum FetchResult: Equatable, Sendable { case ok(Usage), unauthorized, rateLimited, failed }`
  - `public protocol UsageFetching: Sendable { func fetch(token: String) async -> FetchResult }`
  - `public struct UsageClient: UsageFetching { static let endpoint: URL; static func makeRequest(token: String) -> URLRequest; static func interpret(status: Int, data: Data) -> FetchResult; init(session: URLSession = .shared) }`

- [ ] **Step 1: 파서 테스트 작성** — `Tests/ClaudeRingsCoreTests/UsageTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

let sampleUsageJSON = """
{
  "five_hour": { "utilization": 24.0, "resets_at": "2026-09-18T10:00:00.123456+00:00" },
  "seven_day": { "utilization": 20, "resets_at": "2026-09-20T03:00:00+00:00" },
  "seven_day_opus": null,
  "extra_usage": null
}
"""

struct UsageTests {
    @Test func parsesSessionAndWeekly() throws {
        let usage = try #require(UsageParser.parse(Data(sampleUsageJSON.utf8)))

        #expect(usage.session?.utilization == 24.0)
        #expect(usage.session?.remainingPercent == 76)
        #expect(usage.weekly?.remainingPercent == 80)
    }

    @Test func parsesResetDatesWithAndWithoutFraction() throws {
        let usage = try #require(UsageParser.parse(Data(sampleUsageJSON.utf8)))
        let session = try #require(usage.session?.resetsAt)
        let weekly = try #require(usage.weekly?.resetsAt)

        #expect(abs(session.timeIntervalSince1970 - 1_789_725_600.123) < 0.01)
        #expect(weekly.timeIntervalSince1970 == 1_789_873_200)
    }

    @Test func missingOrNullWindowsBecomeNil() throws {
        let usage = try #require(UsageParser.parse(Data(#"{"five_hour":null}"#.utf8)))

        #expect(usage.session == nil)
        #expect(usage.weekly == nil)
    }

    @Test func missingResetDateIsNil() throws {
        let usage = try #require(UsageParser.parse(Data(#"{"five_hour":{"utilization":10}}"#.utf8)))

        #expect(usage.session?.remainingPercent == 90)
        #expect(usage.session?.resetsAt == nil)
    }

    @Test func nonObjectReturnsNil() {
        #expect(UsageParser.parse(Data("[1,2]".utf8)) == nil)
        #expect(UsageParser.parse(Data("not json".utf8)) == nil)
    }

    @Test(arguments: [(0.0, 100), (0.4, 100), (99.6, 0), (120.0, 0), (-5.0, 100), (50.5, 50)])
    func remainingPercentIsRoundedAndClamped(utilization: Double, expected: Int) {
        #expect(UsageWindow(utilization: utilization, resetsAt: nil).remainingPercent == expected)
    }
}
```

> `50.5` 사용 → 잔여 49.5 → `rounded()`는 0.5에서 0에서 먼 쪽으로 반올림하므로 50.

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter UsageTests`
Expected: 컴파일 실패 — `cannot find 'UsageParser' in scope`

- [ ] **Step 3: 구현** — `Sources/ClaudeRingsCore/Usage.swift`

```swift
import Foundation

public struct UsageWindow: Equatable, Sendable {
    /// 사용률(0~100)
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// 남은 비율(0~100, 정수)
    public var remainingPercent: Int {
        max(0, min(100, Int((100 - utilization).rounded())))
    }
}

public struct Usage: Equatable, Sendable {
    public var session: UsageWindow?
    public var weekly: UsageWindow?

    public init(session: UsageWindow?, weekly: UsageWindow?) {
        self.session = session
        self.weekly = weekly
    }
}

/// 비공식 API라 스키마가 바뀔 수 있으므로 필드별로 관대하게 파싱한다.
public enum UsageParser {
    public static func parse(_ data: Data) -> Usage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return Usage(session: window(root["five_hour"]), weekly: window(root["seven_day"]))
    }

    static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return UsageWindow(
            utilization: utilization,
            resetsAt: (dict["resets_at"] as? String).flatMap(parseDate))
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        // 마이크로초(6자리) 등 포매터가 못 읽는 소수부는 밀리초로 줄여 다시 시도한다.
        guard let dot = string.firstIndex(of: "."),
              let end = string[dot...].firstIndex(where: { !$0.isNumber && $0 != "." })
        else { return nil }
        let fraction = string[string.index(after: dot)..<end].prefix(3)
        let trimmed = string[..<dot] + "." + fraction + string[end...]
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(trimmed))
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter UsageTests`
Expected: 모든 테스트 통과(파라미터 테스트 6건 포함)

- [ ] **Step 5: 클라이언트 테스트 작성** — `Tests/ClaudeRingsCoreTests/UsageClientTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

struct UsageClientTests {
    @Test func requestHasRequiredHeaders() {
        let request = UsageClient.makeRequest(token: "tok")

        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.timeoutInterval == 10)
    }

    @Test func okWithValidBody() {
        let result = UsageClient.interpret(status: 200, data: Data(sampleUsageJSON.utf8))
        guard case .ok(let usage) = result else {
            Issue.record("expected .ok, got \(result)")
            return
        }
        #expect(usage.session?.remainingPercent == 76)
    }

    @Test func okWithUnparsableBodyIsFailed() {
        #expect(UsageClient.interpret(status: 200, data: Data("garbage".utf8)) == .failed)
    }

    @Test(arguments: [
        (401, FetchResult.unauthorized),
        (403, .unauthorized),
        (429, .rateLimited),
        (500, .failed),
        (0, .failed),
    ])
    func mapsStatusCodes(status: Int, expected: FetchResult) {
        #expect(UsageClient.interpret(status: status, data: Data()) == expected)
    }
}
```

- [ ] **Step 6: 실패 확인**

Run: `swift test --filter UsageClientTests`
Expected: 컴파일 실패 — `cannot find 'UsageClient' in scope`

- [ ] **Step 7: 구현** — `Sources/ClaudeRingsCore/UsageClient.swift`

```swift
import Foundation

public enum FetchResult: Equatable, Sendable {
    case ok(Usage)
    case unauthorized
    case rateLimited
    case failed
}

public protocol UsageFetching: Sendable {
    func fetch(token: String) async -> FetchResult
}

public struct UsageClient: UsageFetching {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-rings/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func interpret(status: Int, data: Data) -> FetchResult {
        switch status {
        case 200: UsageParser.parse(data).map(FetchResult.ok) ?? .failed
        case 401, 403: .unauthorized
        case 429: .rateLimited
        default: .failed
        }
    }

    public func fetch(token: String) async -> FetchResult {
        do {
            let (data, response) = try await session.data(for: Self.makeRequest(token: token))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.interpret(status: status, data: data)
        } catch {
            return .failed
        }
    }
}
```

- [ ] **Step 8: 통과 확인**

Run: `swift test`
Expected: 전체 통과

- [ ] **Step 9: 커밋**

```bash
git add Sources/ClaudeRingsCore/Usage.swift Sources/ClaudeRingsCore/UsageClient.swift Tests
git commit -m "feat: 사용량 응답 파서와 API 클라이언트 추가"
```

---

### Task 5: 상태, 색상 단계, 백오프, 리셋 시간 표기

**Files:**
- Create: `Sources/ClaudeRingsCore/UsageState.swift`
- Test: `Tests/ClaudeRingsCoreTests/UsageStateTests.swift`

**Interfaces:**
- Consumes: `Usage`, `FetchResult` (Task 4)
- Produces:
  - `public enum AccountStatus: Equatable, Sendable { case loading, ok(Usage), stale(Usage), expired, missing, error; var usage: Usage? }`
  - `public enum RingLevel: Equatable, Sendable { case good, warning, critical, unavailable; init(remaining: Int?) }`
  - `public enum StatusReducer { static func next(previous: AccountStatus, result: FetchResult) -> AccountStatus }`
  - `public struct Backoff: Equatable, Sendable { init(base: TimeInterval, maximum: TimeInterval = 900); var interval: TimeInterval; mutating func recordFailure(); mutating func recordSuccess() }`
  - `public enum ResetFormatter { static func string(until date: Date, now: Date = .now) -> String }`

- [ ] **Step 1: 테스트 작성** — `Tests/ClaudeRingsCoreTests/UsageStateTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

struct UsageStateTests {
    let usage = Usage(session: UsageWindow(utilization: 24, resetsAt: nil), weekly: nil)

    @Test(arguments: [
        (100, RingLevel.good), (50, .good), (49, .warning), (20, .warning), (19, .critical), (0, .critical),
    ])
    func ringLevelThresholds(remaining: Int, expected: RingLevel) {
        #expect(RingLevel(remaining: remaining) == expected)
    }

    @Test func ringLevelWithoutValueIsUnavailable() {
        #expect(RingLevel(remaining: nil) == .unavailable)
    }

    @Test func okResultBecomesOk() {
        #expect(StatusReducer.next(previous: .loading, result: .ok(usage)) == .ok(usage))
    }

    @Test func unauthorizedBecomesExpired() {
        #expect(StatusReducer.next(previous: .ok(usage), result: .unauthorized) == .expired)
    }

    @Test func transientFailureKeepsPreviousUsageAsStale() {
        #expect(StatusReducer.next(previous: .ok(usage), result: .rateLimited) == .stale(usage))
        #expect(StatusReducer.next(previous: .stale(usage), result: .failed) == .stale(usage))
    }

    @Test func transientFailureWithoutUsageIsError() {
        #expect(StatusReducer.next(previous: .loading, result: .failed) == .error)
        #expect(StatusReducer.next(previous: .expired, result: .rateLimited) == .error)
    }

    @Test func backoffDoublesUpToMaximumAndResets() {
        var backoff = Backoff(base: 180)
        #expect(backoff.interval == 180)
        backoff.recordFailure()
        #expect(backoff.interval == 360)
        backoff.recordFailure()
        #expect(backoff.interval == 720)
        backoff.recordFailure()
        #expect(backoff.interval == 900)
        for _ in 0..<100 { backoff.recordFailure() }
        #expect(backoff.interval == 900)
        backoff.recordSuccess()
        #expect(backoff.interval == 180)
    }

    @Test(arguments: [
        (2 * 3600 + 51 * 60, "2h 51m"),
        (39 * 3600, "1d 15h"),
        (12 * 60 + 30, "12m"),
        (20, "1m"),
        (0, "곧"),
        (-100, "곧"),
    ])
    func resetFormatting(seconds: Int, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ResetFormatter.string(until: now.addingTimeInterval(TimeInterval(seconds)), now: now) == expected)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter UsageStateTests`
Expected: 컴파일 실패 — `cannot find 'RingLevel' in scope`

- [ ] **Step 3: 구현** — `Sources/ClaudeRingsCore/UsageState.swift`

```swift
import Foundation

public enum AccountStatus: Equatable, Sendable {
    case loading
    case ok(Usage)
    case stale(Usage)
    case expired
    case missing
    case error

    public var usage: Usage? {
        switch self {
        case .ok(let usage), .stale(let usage): usage
        default: nil
        }
    }
}

public enum RingLevel: Equatable, Sendable {
    case good, warning, critical, unavailable

    public init(remaining: Int?) {
        switch remaining {
        case nil: self = .unavailable
        case let value? where value >= 50: self = .good
        case let value? where value >= 20: self = .warning
        default: self = .critical
        }
    }
}

public enum StatusReducer {
    public static func next(previous: AccountStatus, result: FetchResult) -> AccountStatus {
        switch result {
        case .ok(let usage): .ok(usage)
        case .unauthorized: .expired
        case .rateLimited, .failed: previous.usage.map(AccountStatus.stale) ?? .error
        }
    }
}

public struct Backoff: Equatable, Sendable {
    public let base: TimeInterval
    public let maximum: TimeInterval
    public private(set) var failures = 0

    public init(base: TimeInterval, maximum: TimeInterval = 900) {
        self.base = base
        self.maximum = maximum
    }

    public var interval: TimeInterval {
        min(maximum, base * pow(2, Double(failures)))
    }

    public mutating func recordFailure() {
        failures = min(failures + 1, 16)
    }

    public mutating func recordSuccess() {
        failures = 0
    }
}

public enum ResetFormatter {
    public static func string(until date: Date, now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "곧" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter UsageStateTests`
Expected: 전체 통과

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeRingsCore/UsageState.swift Tests/ClaudeRingsCoreTests/UsageStateTests.swift
git commit -m "feat: 계정 상태, 색상 단계, 백오프, 리셋 시간 표기 추가"
```

---

### Task 6: AccountPoller (토큰 → 조회 → 401 재시도 → 상태)

**Files:**
- Create: `Sources/ClaudeRingsCore/AccountPoller.swift`
- Test: `Tests/ClaudeRingsCoreTests/AccountPollerTests.swift`

**Interfaces:**
- Consumes: `TokenProvider`, `TokenError` (Task 3), `UsageFetching`, `FetchResult` (Task 4), `AccountStatus`, `StatusReducer` (Task 5)
- Produces:
  - `public struct AccountPoller: Sendable { init(tokens: any TokenProvider, fetcher: any UsageFetching); func poll(_ account: Account, previous: AccountStatus) async -> PollOutcome }`
  - `public struct PollOutcome: Equatable, Sendable { let status: AccountStatus; let transientFailure: Bool }`

- [ ] **Step 1: 테스트 작성** — `Tests/ClaudeRingsCoreTests/AccountPollerTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

final class StubTokens: TokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<String, TokenError>]
    private(set) var calls = 0

    init(_ queue: [Result<String, TokenError>]) { self.queue = queue }

    func accessToken(for account: Account) throws(TokenError) -> String {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        let next = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try next.get()
    }
}

final class StubFetcher: UsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [FetchResult]
    private(set) var tokensSeen: [String] = []

    init(_ queue: [FetchResult]) { self.queue = queue }

    func fetch(token: String) async -> FetchResult {
        lock.withLock {
            tokensSeen.append(token)
            return queue.count > 1 ? queue.removeFirst() : queue[0]
        }
    }
}

struct AccountPollerTests {
    let account = Account(name: "work", configDir: "~/.claude/work")
    let usage = Usage(session: UsageWindow(utilization: 10, resetsAt: nil), weekly: nil)

    @Test func successReturnsOk() async {
        let poller = AccountPoller(tokens: StubTokens([.success("t1")]), fetcher: StubFetcher([.ok(usage)]))

        let outcome = await poller.poll(account, previous: .loading)

        #expect(outcome == PollOutcome(status: .ok(usage), transientFailure: false))
    }

    @Test func missingTokenSkipsFetch() async {
        let fetcher = StubFetcher([.ok(usage)])
        let poller = AccountPoller(tokens: StubTokens([.failure(.notFound)]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .loading)

        #expect(outcome == PollOutcome(status: .missing, transientFailure: false))
        #expect(fetcher.tokensSeen.isEmpty)
    }

    @Test func deniedTokenIsMissing() async {
        let poller = AccountPoller(tokens: StubTokens([.failure(.accessDenied)]), fetcher: StubFetcher([.ok(usage)]))
        #expect(await poller.poll(account, previous: .loading).status == .missing)
    }

    @Test func malformedTokenIsError() async {
        let poller = AccountPoller(tokens: StubTokens([.failure(.malformed)]), fetcher: StubFetcher([.ok(usage)]))
        #expect(await poller.poll(account, previous: .loading).status == .error)
    }

    @Test func unauthorizedRereadsTokenAndRetriesOnce() async {
        let tokens = StubTokens([.success("old"), .success("new")])
        let fetcher = StubFetcher([.unauthorized, .ok(usage)])
        let poller = AccountPoller(tokens: tokens, fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .expired)

        #expect(outcome.status == .ok(usage))
        #expect(fetcher.tokensSeen == ["old", "new"])
        #expect(tokens.calls == 2)
    }

    @Test func unauthorizedTwiceIsExpired() async {
        let fetcher = StubFetcher([.unauthorized])
        let poller = AccountPoller(tokens: StubTokens([.success("t")]), fetcher: fetcher)

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .expired, transientFailure: false))
        #expect(fetcher.tokensSeen.count == 2)
    }

    @Test func rateLimitedKeepsStaleAndReportsTransientFailure() async {
        let poller = AccountPoller(tokens: StubTokens([.success("t")]), fetcher: StubFetcher([.rateLimited]))

        let outcome = await poller.poll(account, previous: .ok(usage))

        #expect(outcome == PollOutcome(status: .stale(usage), transientFailure: true))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter AccountPollerTests`
Expected: 컴파일 실패 — `cannot find 'AccountPoller' in scope`

- [ ] **Step 3: 구현** — `Sources/ClaudeRingsCore/AccountPoller.swift`

```swift
import Foundation

public struct PollOutcome: Equatable, Sendable {
    public let status: AccountStatus
    /// 429·네트워크 오류처럼 백오프가 필요한 실패인지
    public let transientFailure: Bool

    public init(status: AccountStatus, transientFailure: Bool) {
        self.status = status
        self.transientFailure = transientFailure
    }
}

public struct AccountPoller: Sendable {
    private let tokens: any TokenProvider
    private let fetcher: any UsageFetching

    public init(tokens: any TokenProvider, fetcher: any UsageFetching) {
        self.tokens = tokens
        self.fetcher = fetcher
    }

    public func poll(_ account: Account, previous: AccountStatus) async -> PollOutcome {
        let token: String
        do {
            token = try tokens.accessToken(for: account)
        } catch let error as TokenError {
            return PollOutcome(status: error == .malformed ? .error : .missing, transientFailure: false)
        } catch {
            // typed throws 추론이 켜진 툴체인에서는 도달하지 않는다(경고는 무시해도 됨).
            return PollOutcome(status: .error, transientFailure: false)
        }

        var result = await fetcher.fetch(token: token)
        // Claude Code가 그 사이 토큰을 갱신했을 수 있으므로 Keychain을 다시 읽어 한 번만 재시도한다.
        if result == .unauthorized, let refreshed = try? tokens.accessToken(for: account) {
            result = await fetcher.fetch(token: refreshed)
        }

        return PollOutcome(
            status: StatusReducer.next(previous: previous, result: result),
            transientFailure: result == .rateLimited || result == .failed)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter AccountPollerTests`
Expected: 7 tests passed

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeRingsCore/AccountPoller.swift Tests/ClaudeRingsCoreTests/AccountPollerTests.swift
git commit -m "feat: 계정 조회기(401 재시도 포함) 추가"
```

---

### Task 7: SessionWatcher (세션 추적과 종료 판단)

**Files:**
- Create: `Sources/ClaudeRingsCore/SessionWatcher.swift`
- Test: `Tests/ClaudeRingsCoreTests/SessionWatcherTests.swift`

**Interfaces:**
- Consumes: `KeychainService.normalize` (Task 3)
- Produces:
  - `public protocol ProcessChecker: Sendable { func isAlive(_ pid: Int32) -> Bool }`
  - `public struct KillProcessChecker: ProcessChecker`
  - `public struct SessionSnapshot: Equatable, Sendable { let activeConfigDirs: Set<String>; let shouldQuit: Bool }`
  - `public struct SessionWatcher: Sendable { init(directory: URL = SessionWatcher.defaultDirectory, checker: any ProcessChecker = KillProcessChecker(), grace: TimeInterval = 10, home: String = NSHomeDirectory()); static var defaultDirectory: URL; mutating func tick(now: Date = .now) -> SessionSnapshot }`

- [ ] **Step 1: 테스트 작성** — `Tests/ClaudeRingsCoreTests/SessionWatcherTests.swift`

```swift
import Foundation
import Testing
@testable import ClaudeRingsCore

struct FakeChecker: ProcessChecker {
    var alive: Set<Int32>
    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
}

struct SessionWatcherTests {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "claude-rings-sessions-\(UUID().uuidString)")
    let home = "/Users/alice"
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func writeSession(pid: Int32, configDir: String) throws {
        try Data("\(configDir)\n".utf8).write(to: dir.appending(path: "\(pid)"))
    }

    func watcher(alive: Set<Int32>) -> SessionWatcher {
        SessionWatcher(directory: dir, checker: FakeChecker(alive: alive), grace: 10, home: home)
    }

    @Test func collectsNormalizedConfigDirsOfLiveSessions() throws {
        try writeSession(pid: 100, configDir: "~/.claude/work")
        try writeSession(pid: 200, configDir: "/Users/alice/.claude/")
        var sut = watcher(alive: [100, 200])

        let snapshot = sut.tick(now: t0)

        #expect(snapshot.activeConfigDirs == ["/Users/alice/.claude/work", "/Users/alice/.claude"])
        #expect(snapshot.shouldQuit == false)
    }

    @Test func removesFilesOfDeadSessions() throws {
        try writeSession(pid: 100, configDir: "~/.claude/work")
        try writeSession(pid: 300, configDir: "~/.claude")
        var sut = watcher(alive: [100])

        let snapshot = sut.tick(now: t0)

        #expect(snapshot.activeConfigDirs == ["/Users/alice/.claude/work"])
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "300").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "100").path))
    }

    @Test func ignoresNonNumericFiles() throws {
        try Data("x".utf8).write(to: dir.appending(path: ".DS_Store"))
        var sut = watcher(alive: [])

        _ = sut.tick(now: t0)

        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".DS_Store").path))
    }

    @Test func quitsOnlyAfterGracePeriodWithNoSessions() {
        var sut = watcher(alive: [])

        #expect(sut.tick(now: t0).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(5)).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(10)).shouldQuit == true)
    }

    @Test func newSessionResetsGracePeriod() throws {
        var sut = watcher(alive: [100])

        _ = sut.tick(now: t0)
        try writeSession(pid: 100, configDir: "~/.claude")
        #expect(sut.tick(now: t0.addingTimeInterval(8)).shouldQuit == false)
        try FileManager.default.removeItem(at: dir.appending(path: "100"))
        #expect(sut.tick(now: t0.addingTimeInterval(12)).shouldQuit == false)
        #expect(sut.tick(now: t0.addingTimeInterval(22)).shouldQuit == true)
    }

    @Test func missingDirectoryCountsAsNoSessions() {
        var sut = SessionWatcher(
            directory: dir.appending(path: "nope"), checker: FakeChecker(alive: []), grace: 0, home: home)
        #expect(sut.tick(now: t0).shouldQuit == true)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter SessionWatcherTests`
Expected: 컴파일 실패 — `cannot find type 'ProcessChecker' in scope`

- [ ] **Step 3: 구현** — `Sources/ClaudeRingsCore/SessionWatcher.swift`

```swift
import Foundation

public protocol ProcessChecker: Sendable {
    func isAlive(_ pid: Int32) -> Bool
}

public struct KillProcessChecker: ProcessChecker {
    public init() {}

    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public let activeConfigDirs: Set<String>
    public let shouldQuit: Bool
}

/// `~/.claude-rings/sessions/<셸 PID>` 파일(내용: config 경로)로 실행 중인 세션을 추적한다.
public struct SessionWatcher: Sendable {
    public let directory: URL
    private let checker: any ProcessChecker
    private let grace: TimeInterval
    private let home: String
    private var emptySince: Date?

    public init(
        directory: URL = SessionWatcher.defaultDirectory,
        checker: any ProcessChecker = KillProcessChecker(),
        grace: TimeInterval = 10,
        home: String = NSHomeDirectory()
    ) {
        self.directory = directory
        self.checker = checker
        self.grace = grace
        self.home = home
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude-rings/sessions")
    }

    public mutating func tick(now: Date = .now) -> SessionSnapshot {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var active = Set<String>()
        var liveCount = 0

        for name in names {
            guard let pid = Int32(name) else { continue }
            let file = directory.appending(path: name)
            guard checker.isAlive(pid) else {
                try? fileManager.removeItem(at: file)
                continue
            }
            liveCount += 1
            let content = (try? String(contentsOf: file, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !content.isEmpty {
                active.insert(KeychainService.normalize(content, home: home))
            }
        }

        if liveCount > 0 {
            emptySince = nil
            return SessionSnapshot(activeConfigDirs: active, shouldQuit: false)
        }
        let since = emptySince ?? now
        emptySince = since
        return SessionSnapshot(activeConfigDirs: [], shouldQuit: now.timeIntervalSince(since) >= grace)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: 전체 통과

- [ ] **Step 5: 커밋**

```bash
git add Sources/ClaudeRingsCore/SessionWatcher.swift Tests/ClaudeRingsCoreTests/SessionWatcherTests.swift
git commit -m "feat: 세션 추적과 자동 종료 판단 추가"
```

---

### Task 8: 앱 뼈대 — 항상 위 패널과 조회 루프

UI는 단위 테스트하지 않고 실행해서 확인한다. 이 작업이 끝나면 숫자만 있는 간단한 뷰가 화면 우상단에 떠야 한다(Liquid Glass는 Task 9).

**Files:**
- Modify: `Sources/ClaudeRings/main.swift` (전체 교체)
- Create: `Sources/ClaudeRings/AppDelegate.swift`
- Create: `Sources/ClaudeRings/UsageViewModel.swift`
- Create: `Sources/ClaudeRings/RingsPanel.swift`
- Create: `Sources/ClaudeRings/RingsView.swift` (임시 뷰, Task 9에서 교체)

**Interfaces:**
- Consumes: `AccountStore`, `AppConfig`, `Account` (Task 2), `KeychainService`, `KeychainTokenProvider` (Task 3), `UsageClient` (Task 4), `AccountStatus`, `Backoff` (Task 5), `AccountPoller` (Task 6), `SessionWatcher` (Task 7)
- Produces (Task 9가 사용):
  - `@MainActor @Observable final class UsageViewModel { let accounts: [Account]; func status(for: Account) -> AccountStatus; func isActive(_: Account) -> Bool; var activeConfigDirs: Set<String>; func start(); func refreshAll() }`
  - `struct RingsActions { let refresh, resetPosition, openConfig, quit: @MainActor () -> Void }`
  - `struct RingsView: View { init(model: UsageViewModel, actions: RingsActions, onSizeChange: @escaping @MainActor (CGSize) -> Void) }`

- [ ] **Step 1: `main.swift` 교체**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: `UsageViewModel.swift` 작성**

```swift
import ClaudeRingsCore
import Foundation
import Observation

@MainActor
@Observable
final class UsageViewModel {
    let accounts: [Account]
    private(set) var statuses: [String: AccountStatus]
    var activeConfigDirs: Set<String> = []

    @ObservationIgnored private let poller: AccountPoller
    @ObservationIgnored private let baseInterval: TimeInterval
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(config: AppConfig, poller: AccountPoller) {
        accounts = config.accounts
        statuses = Dictionary(config.accounts.map { ($0.name, AccountStatus.loading) }, uniquingKeysWith: { first, _ in first })
        self.poller = poller
        baseInterval = TimeInterval(max(30, config.pollIntervalSeconds))
    }

    func status(for account: Account) -> AccountStatus {
        statuses[account.name] ?? .loading
    }

    func isActive(_ account: Account) -> Bool {
        activeConfigDirs.contains(KeychainService.normalize(account.configDir))
    }

    func start() {
        for account in accounts {
            startLoop(for: account)
        }
    }

    func refreshAll() {
        start()
    }

    private func startLoop(for account: Account) {
        tasks[account.name]?.cancel()
        let poller = poller
        let base = baseInterval
        tasks[account.name] = Task { [weak self] in
            var backoff = Backoff(base: base)
            while !Task.isCancelled {
                let previous = self?.status(for: account) ?? .loading
                let outcome = await poller.poll(account, previous: previous)
                guard !Task.isCancelled, let self else { return }
                self.statuses[account.name] = outcome.status
                if outcome.transientFailure {
                    backoff.recordFailure()
                } else {
                    backoff.recordSuccess()
                }
                try? await Task.sleep(for: .seconds(backoff.interval))
            }
        }
    }
}
```

- [ ] **Step 3: `RingsPanel.swift` 작성**

```swift
import AppKit
import SwiftUI

struct RingsActions {
    let refresh: @MainActor () -> Void
    let resetPosition: @MainActor () -> Void
    let openConfig: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

/// 창 자체는 투명하고 SwiftUI 콘텐츠만 보이는, 모든 Space의 항상 위 패널.
/// 콘텐츠 크기가 바뀌면 오른쪽 위 모서리를 기준으로 크기를 맞춘다.
@MainActor
final class RingsPanel: NSPanel {
    private static let anchorKey = "panelTopRight"
    private static let margin = CGSize(width: 16, height: 12)

    init(model: UsageViewModel, actions: RingsActions) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true

        let root = RingsView(model: model, actions: actions) { [weak self] size in
            self?.fit(to: size)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        contentView = hosting

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
        fit(to: frame.size)
    }

    private func fit(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let topRight = savedTopRight ?? defaultTopRight
        setFrame(
            NSRect(x: topRight.x - size.width, y: topRight.y - size.height, width: size.width, height: size.height),
            display: true)
    }

    private var savedTopRight: CGPoint? {
        UserDefaults.standard.string(forKey: Self.anchorKey).map(NSPointFromString)
    }

    private var defaultTopRight: CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: visible.maxX - Self.margin.width, y: visible.maxY - Self.margin.height)
    }

    @objc private func didMove(_ notification: Notification) {
        UserDefaults.standard.set(
            NSStringFromPoint(NSPoint(x: frame.maxX, y: frame.maxY)), forKey: Self.anchorKey)
    }
}
```

- [ ] **Step 4: 임시 `RingsView.swift` 작성**

```swift
import ClaudeRingsCore
import SwiftUI

struct RingsView: View {
    let model: UsageViewModel
    let actions: RingsActions
    let onSizeChange: @MainActor (CGSize) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.accounts) { account in
                let usage = model.status(for: account).usage
                VStack {
                    Text(account.name)
                    Text("\(usage?.session?.remainingPercent ?? -1) / \(usage?.weekly?.remainingPercent ?? -1)")
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }
}
```

- [ ] **Step 5: `AppDelegate.swift` 작성**

```swift
import AppKit
import ClaudeRingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AccountStore()
    private let standalone = CommandLine.arguments.contains("--standalone")
    private var sessions = SessionWatcher()
    private var model: UsageViewModel?
    private var panel: RingsPanel?
    private var sessionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageViewModel(
            config: store.load(),
            poller: AccountPoller(tokens: KeychainTokenProvider(), fetcher: UsageClient()))
        let store = store
        let panel = RingsPanel(
            model: model,
            actions: RingsActions(
                refresh: { [weak model] in model?.refreshAll() },
                resetPosition: { [weak self] in self?.panel?.resetPosition() },
                openConfig: { NSWorkspace.shared.open(store.fileURL) },
                quit: { NSApp.terminate(nil) }))
        self.model = model
        self.panel = panel

        panel.orderFrontRegardless()
        model.start()
        checkSessions()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSessions() }
        }
    }

    private func checkSessions() {
        let snapshot = sessions.tick()
        model?.activeConfigDirs = snapshot.activeConfigDirs
        if snapshot.shouldQuit && !standalone {
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 6: 빌드 확인**

Run: `swift build`
Expected: `Build complete!` (경고는 허용, 오류 없음)

- [ ] **Step 7: 실행 확인**

Run: `swift run ClaudeRings --standalone` (확인 후 Ctrl-C로 종료)
Expected:
- 화면 우상단에 계정 이름과 `남은 Session / 남은 Weekly` 숫자가 보임(최초 몇 초는 `-1 / -1`)
- 다른 앱을 클릭해도 패널이 가려지지 않음
- 터미널 포커스를 빼앗지 않음

- [ ] **Step 8: 세션 종료 확인**

Run: `swift run ClaudeRings` (`--standalone` 없이, 세션 파일 없는 상태)
Expected: 약 10초 뒤 앱이 스스로 종료됨

- [ ] **Step 9: 커밋**

```bash
git add Sources/ClaudeRings
git commit -m "feat: 항상 위 패널과 계정별 조회 루프 추가"
```

---

### Task 9: Liquid Glass 링 UI

**Files:**
- Modify: `Sources/ClaudeRings/RingsView.swift` (전체 교체)

**Interfaces:**
- Consumes: `UsageViewModel`, `RingsActions` (Task 8), `AccountStatus`, `RingLevel`, `ResetFormatter` (Task 5), `UsageWindow` (Task 4)
- Produces: `struct RingsView: View` (Task 8과 같은 이니셜라이저 유지)

- [ ] **Step 1: `RingsView.swift` 교체**

```swift
import ClaudeRingsCore
import SwiftUI

struct RingsView: View {
    let model: UsageViewModel
    let actions: RingsActions
    let onSizeChange: @MainActor (CGSize) -> Void

    @State private var hovered: String?
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.accounts) { account in
                    AccountBubble(
                        account: account,
                        status: model.status(for: account),
                        isActive: model.isActive(account),
                        isExpanded: hovered == account.name,
                        namespace: glassNamespace)
                    .onHover { inside in
                        withAnimation(.spring(duration: 0.35)) {
                            if inside {
                                hovered = account.name
                            } else if hovered == account.name {
                                hovered = nil
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .fixedSize()
        .gesture(WindowDragGesture())
        .contextMenu {
            Button("지금 새로고침", action: actions.refresh)
            Button("위치 초기화", action: actions.resetPosition)
            Button("설정 파일 열기", action: actions.openConfig)
            Divider()
            Button("종료", action: actions.quit)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }
}

private struct AccountBubble: View {
    let account: Account
    let status: AccountStatus
    let isActive: Bool
    let isExpanded: Bool
    let namespace: Namespace.ID

    private var session: UsageWindow? { status.usage?.session }
    private var weekly: UsageWindow? { status.usage?.weekly }

    private var isStale: Bool {
        if case .stale = status { true } else { false }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    DualRing(
                        outer: session?.remainingPercent,
                        inner: weekly?.remainingPercent,
                        isLoading: status == .loading,
                        isDashed: status == .missing)
                    center
                }
                .frame(width: 56, height: 56)

                if isExpanded {
                    details
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(4)
            .opacity(isStale ? 0.5 : 1)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID(account.name, in: namespace)

            HStack(spacing: 3) {
                Text(account.name)
                if isActive {
                    Circle().fill(.tint).frame(width: 4, height: 4)
                }
            }
            .font(.system(size: 10, weight: isActive ? .semibold : .regular, design: .rounded))
            .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private var center: some View {
        switch status {
        case .loading:
            EmptyView()
        case .expired:
            Text("만료")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        case .missing:
            Text("로그인\n필요")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
        case .ok, .stale:
            VStack(spacing: 0) {
                Text(session.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(weekly.map { "\($0.remainingPercent)" } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            detailRow(title: "Session", window: session)
            detailRow(title: "Weekly", window: weekly)
        }
        .font(.system(size: 11, design: .rounded))
        .padding(.trailing, 10)
        .fixedSize()
    }

    private func detailRow(title: String, window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(window?.resetsAt.map { "\(ResetFormatter.string(until: $0)) 후 리셋" } ?? "—")
        }
    }
}

private struct DualRing: View {
    let outer: Int?
    let inner: Int?
    let isLoading: Bool
    let isDashed: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            ring(value: outer, lineWidth: 5).padding(2)
            ring(value: inner, lineWidth: 4).padding(10)
        }
        .opacity(isLoading ? (pulse ? 0.35 : 0.1) : 1)
        .animation(isLoading ? .easeInOut(duration: 1).repeatForever() : .default, value: pulse)
        .animation(.spring(duration: 0.6), value: outer)
        .animation(.spring(duration: 0.6), value: inner)
        .onAppear { pulse = true }
    }

    private func ring(value: Int?, lineWidth: CGFloat) -> some View {
        let color = RingLevel(remaining: value).color
        let track = StrokeStyle(lineWidth: lineWidth, dash: isDashed ? [2, 3] : [])
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.15), style: track)
            Circle()
                .trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private extension RingLevel {
    var color: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        case .unavailable: .gray
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 수동 확인**

Run: `swift run ClaudeRings --standalone`
Expected(모두 확인):
- 계정별 원형 유리 버블, 바깥 링 = Session, 안쪽 링 = Weekly, 중앙에 두 숫자
- 색상 단계가 남은 %에 맞음
- 마우스를 올리면 버블이 캡슐로 늘어나며 리셋 시각이 보이고, 내리면 원래대로 돌아옴
- 드래그로 이동 → 앱 재실행 시 같은 위치
- 우클릭 메뉴 4개 항목 동작
- 라이트/다크 모드, 다른 Space, 전체 화면 앱 위에서 모두 보임

호버가 반응하지 않으면 `RingsPanel`의 `canBecomeKey`를 유지한 채 `.onContinuousHover`로 바꿔 다시 확인한다. 드래그가 안 되면 `.gesture(WindowDragGesture())`를 제거하고 `isMovableByWindowBackground`만으로 확인한다. 어떤 방법을 택했는지 커밋 메시지에 적는다.

- [ ] **Step 4: 커밋**

```bash
git add Sources/ClaudeRings/RingsView.swift
git commit -m "feat: Liquid Glass 이중 링 UI 추가"
```

---

### Task 10: `.app` 번들 빌드와 설치

**Files:**
- Create: `Support/Info.plist`
- Create: `scripts/build-app.sh`
- Modify: `README.md` ("설치 · 사용법" 섹션)

**Interfaces:**
- Consumes: `ClaudeRings` 실행 파일 (Task 8)
- Produces: `~/Applications/ClaudeRings.app` (Task 11의 셸 함수가 실행)

- [ ] **Step 1: `Support/Info.plist` 작성**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.loisrk.claude-rings</string>
    <key>CFBundleName</key>
    <string>ClaudeRings</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeRings</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: `scripts/build-app.sh` 작성**

```bash
#!/usr/bin/env bash
# 릴리스 빌드 후 build/ClaudeRings.app을 만든다. --install이면 ~/Applications에 복사한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClaudeRings
bin_dir="$(swift build -c release --show-bin-path)"

app="build/ClaudeRings.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/ClaudeRings" "$app/Contents/MacOS/ClaudeRings"
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "built: $app"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ClaudeRings.app"
  cp -R "$app" "$HOME/Applications/"
  echo "installed: $HOME/Applications/ClaudeRings.app"
fi
```

- [ ] **Step 3: 빌드·설치 확인**

Run: `chmod +x scripts/build-app.sh && scripts/build-app.sh --install`
Expected: `built: build/ClaudeRings.app`, `installed: .../Applications/ClaudeRings.app`

- [ ] **Step 4: 번들 실행 확인**

Run: `open "$HOME/Applications/ClaudeRings.app" --args --standalone`
Expected: Dock 아이콘 없이 패널만 뜸. 우클릭 → 종료로 닫힘

- [ ] **Step 5: README "설치 · 사용법" 섹션 교체**

`README.md`의 `구현 완료 후 작성 예정입니다.` 줄을 아래로 바꾼다.

````markdown
1. 빌드 및 설치

   ```bash
   git clone https://github.com/loisRK/claude-rings.git
   cd claude-rings
   scripts/build-app.sh --install   # ~/Applications/ClaudeRings.app
   ```

2. 계정 등록 — 최초 실행 시 `~/.config/claude-rings/accounts.json`이 생성됩니다. 추가 계정을 넣으세요.

   ```json
   {
     "accounts": [
       { "name": "main", "configDir": "~/.claude" },
       { "name": "work", "configDir": "~/.claude/work" }
     ],
     "pollIntervalSeconds": 180
   }
   ```

3. 셸 함수 연결 — `~/.zshrc`에 추가합니다.

   ```zsh
   source /path/to/claude-rings/scripts/claude-rings.zsh
   claude-work() { claude_rings_run ~/.claude/work "$@"; }
   ```

   `claude-work`를 실행하면 위젯이 뜨고, 이 함수로 실행한 세션이 모두 끝나면 위젯도 닫힙니다.

4. 위젯 조작 — 드래그로 이동, 마우스를 올리면 리셋 시각 표시, 우클릭으로 새로고침·위치 초기화·설정 열기·종료
````

또한 README "보안" 섹션의 `최초 실행 시 macOS가 Keychain 접근을 묻습니다. **항상 허용**을 선택하세요.`를 `macOS가 Keychain 접근을 물으면 **항상 허용**을 선택하세요.`로 바꾼다.

- [ ] **Step 6: 커밋**

```bash
git add Support/Info.plist scripts/build-app.sh README.md
git commit -m "chore: .app 번들 빌드 스크립트와 설치 안내 추가"
```

---

### Task 11: 셸 함수와 로컬 연결

**Files:**
- Create: `scripts/claude-rings.zsh`
- 로컬 전용(커밋하지 않음): `~/.zshrc`, `~/.config/claude-rings/accounts.json`

**Interfaces:**
- Consumes: `~/Applications/ClaudeRings.app` (Task 10), 세션 파일 규약(Task 7)
- Produces: `claude_rings_run <config-dir> [claude 인자...]`

- [ ] **Step 1: `scripts/claude-rings.zsh` 작성**

```zsh
# claude-rings: CLAUDE_CONFIG_DIR로 claude를 실행하는 동안 사용량 위젯을 띄운다.
# 사용법: claude_rings_run <config-dir> [claude 인자...]
claude_rings_run() {
  local cfg="$1"; shift
  local dir="$HOME/.claude-rings/sessions"
  mkdir -p "$dir" && print -r -- "$cfg" > "$dir/$$"
  pgrep -x ClaudeRings >/dev/null || open -g "$HOME/Applications/ClaudeRings.app"
  CLAUDE_CONFIG_DIR="$cfg" command claude "$@"
  local rc=$?
  rm -f "$dir/$$"
  return $rc
}
```

- [ ] **Step 2: 문법 확인**

Run: `zsh -n scripts/claude-rings.zsh && echo OK`
Expected: `OK`

- [ ] **Step 3: 커밋**

```bash
git add scripts/claude-rings.zsh
git commit -m "feat: 위젯 연동 셸 함수 추가"
```

- [ ] **Step 4: 로컬 설정 변경 — 사용자 확인 필수**

`~/.zshrc`는 설정 파일이므로 **변경 전 사용자에게 아래 diff를 보여주고 승인을 받는다.** 기존 alias 줄을 찾아 교체한다.

```zsh
# 변경 전
alias claude-<alias>='CLAUDE_CONFIG_DIR=~/.claude/<dir> claude'

# 변경 후
source <저장소 경로>/scripts/claude-rings.zsh
claude-<alias>() { claude_rings_run ~/.claude/<dir> "$@"; }
```

주의: zsh는 같은 이름의 alias가 남아 있으면 함수 정의가 alias로 확장되어 오류가 난다. 기존 alias 줄은 반드시 제거(또는 주석 처리)한다.

- [ ] **Step 5: 계정 등록**

`~/.config/claude-rings/accounts.json`에 두 번째 계정을 추가한다(파일이 없으면 앱을 한 번 실행해 생성).

```json
{
  "accounts": [
    { "name": "main", "configDir": "~/.claude" },
    { "name": "<alias>", "configDir": "~/.claude/<dir>" }
  ],
  "pollIntervalSeconds": 180
}
```

- [ ] **Step 6: 전체 흐름 확인**

새 터미널에서:

1. `claude-<alias>` 실행 → 위젯이 뜨고 해당 계정 이름에 • 표시
2. 다른 탭에서도 `claude-<alias>` 실행 → 위젯이 하나만 유지됨
3. 한 탭의 claude 종료 → 위젯 유지
4. 나머지 탭의 claude 종료 → 약 10~15초 안에 위젯 종료
5. claude 실행 중 터미널 창을 강제로 닫음 → 다른 세션이 없으면 위젯 종료

- [ ] **Step 7: 최종 테스트와 푸시**

Run: `swift test && git status --short`
Expected: 전체 통과, 커밋되지 않은 변경 없음

```bash
git push origin main
```
