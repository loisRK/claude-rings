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
            resources: [.process("Resources")]),
        .testTarget(name: "ClaudeRingsCoreTests", dependencies: ["ClaudeRingsCore"]),
    ]
)
