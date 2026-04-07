import XCTest

final class EntitlementsConfigurationTests: XCTestCase {
    func testAudioInputEntitlementIsEnabled() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsPath = root.appendingPathComponent("TeamsAutoRecorder/TeamsAutoRecorder.entitlements")
        let data = try Data(contentsOf: entitlementsPath)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dict = try XCTUnwrap(plist as? [String: Any])
        let enabled = dict["com.apple.security.device.audio-input"] as? Bool

        XCTAssertEqual(
            enabled,
            true,
            "Developer ID builds with hardened runtime need com.apple.security.device.audio-input to access microphone."
        )
    }
}
