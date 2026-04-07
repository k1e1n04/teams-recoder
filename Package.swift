// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeamsAutoRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TeamsAutoRecorder", targets: ["TeamsAutoRecorder"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.7.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TeamsAutoRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
            ],
            exclude: ["App/Main.swift", "Assets.xcassets"]
        ),
        .testTarget(name: "TeamsAutoRecorderTests", dependencies: ["TeamsAutoRecorder"])
    ]
)
