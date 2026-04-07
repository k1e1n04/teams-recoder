import XCTest
@testable import TeamsAutoRecorder

final class SlackHuddleWindowClassifierTests: XCTestCase {
    func testReturnsTrueWhenRequiredKeywordExists() {
        XCTAssertTrue(SlackHuddleWindowClassifier.allKeywordsExist(in: ["退出する"]))
    }

    func testReturnsTrueWhenKeywordExistsAmongMultipleTitles() {
        XCTAssertTrue(SlackHuddleWindowClassifier.allKeywordsExist(in: ["Slack", "退出する", "マイク"]))
    }

    func testReturnsFalseWhenKeywordIsMissing() {
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["退出"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["する"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: []))
    }

    func testReturnsFalseForNormalSlackWindowTitles() {
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["Slack"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: ["general | workspace"]))
        XCTAssertFalse(SlackHuddleWindowClassifier.allKeywordsExist(in: [""]))
    }
}
