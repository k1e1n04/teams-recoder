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
    targets: [
        .target(
            name: "TeamsAutoRecorder",
            exclude: ["App/Main.swift"]
        ),
        .testTarget(name: "TeamsAutoRecorderTests", dependencies: ["TeamsAutoRecorder"])
    ]
)
