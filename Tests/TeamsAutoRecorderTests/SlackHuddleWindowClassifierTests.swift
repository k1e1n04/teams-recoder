import XCTest
@testable import TeamsAutoRecorder

final class SlackHuddleWindowClassifierTests: XCTestCase {
    func testReturnsTrueWhenRequiredKeywordsExist() {
        XCTAssertTrue(SlackHuddleWindowClassifier.allKeywordsExist(in: ["ハドル", "退出する"]))
    }

    func testReturnsTrueWhenKeywordsExistAmongMultipleTitles() {
        XCTAssertTrue(SlackHuddleWindowClassifier.allKeywordsExist(in: ["Slack", "ハドル", "退出する", "マイク"]))
    }

    func testReturnsFalseWhenHuddleKeywordIsMissing() {
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["退出する"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["退出する", "Slack"]))
    }

    func testReturnsFalseWhenLeaveKeywordIsMissing() {
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["ハドル"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["退出"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: []))
    }

    func testReturnsFalseForNormalSlackWindowTitles() {
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["Slack"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["general | workspace"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: [""]))
    }
}
