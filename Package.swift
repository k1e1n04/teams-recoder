// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeamsAutoRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TeamsAutoRecorder", targets: ["TeamsAutoRecorder"]),
        .executable(name: "TeamsAutoRecorderMCP", targets: ["TeamsAutoRecorderMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.7.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TeamsAutoRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ],
            exclude: ["App/Main.swift", "Assets.xcassets"]
        ),
        .executableTarget(
            name: "TeamsAutoRecorderMCP",
            path: "Sources/TeamsAutoRecorderMCP"
        ),
        .testTarget(name: "TeamsAutoRecorderTests", dependencies: ["TeamsAutoRecorder"])
    ]
)
