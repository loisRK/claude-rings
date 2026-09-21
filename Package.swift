// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeRings",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ClaudeRingsCore"),
        .executableTarget(
            name: "ClaudeRings",
            dependencies: ["ClaudeRingsCore"],
            // .process는 폴더 구조를 평평하게 만들어 logos/claude.png가 claude.png로
            // 바뀌어 버린다(검증 중 발견). .copy로 logos/ 폴더 구조를 그대로 보존한다.
            resources: [.copy("Resources/logos")]),
        .testTarget(name: "ClaudeRingsCoreTests", dependencies: ["ClaudeRingsCore"]),
    ]
)
