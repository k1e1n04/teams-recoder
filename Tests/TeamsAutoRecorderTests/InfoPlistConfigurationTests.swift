import XCTest

final class InfoPlistConfigurationTests: XCTestCase {
    func testProjectDefinesMicrophoneUsageDescription() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectYAML = root.appendingPathComponent("project.yml")
        let contents = try String(contentsOf: projectYAML, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("INFOPLIST_KEY_NSMicrophoneUsageDescription:"),
            "project.yml must define NSMicrophoneUsageDescription so macOS can present microphone permission prompt."
        )
    }
}
