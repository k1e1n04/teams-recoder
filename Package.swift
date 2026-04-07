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
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "TeamsAutoRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            exclude: ["App/Main.swift", "Assets.xcassets"]
        ),
        .testTarget(name: "TeamsAutoRecorderTests", dependencies: ["TeamsAutoRecorder"])
    ]
)
