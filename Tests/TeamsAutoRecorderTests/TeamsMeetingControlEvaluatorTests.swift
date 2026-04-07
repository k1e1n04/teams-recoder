import XCTest
@testable import TeamsAutoRecorder

final class TeamsMeetingControlEvaluatorTests: XCTestCase {
    func testReturnsTrueWhenAccessibilityTrustedAndAllKeywordsExist() {
        XCTAssertTrue(
            TeamsMeetingControlEvaluator.isMeetingUIActive(
                accessibilityTrusted: true,
                visibleTexts: ["退出", "共有", "マイク", "カメラ"]
            )
        )
    }

    func testReturnsFalseWhenAccessibilityNotTrusted() {
        XCTAssertFalse(
            TeamsMeetingControlEvaluator.isMeetingUIActive(
                accessibilityTrusted: false,
                visibleTexts: ["退出", "共有", "マイク", "カメラ"]
            )
        )
    }
}
