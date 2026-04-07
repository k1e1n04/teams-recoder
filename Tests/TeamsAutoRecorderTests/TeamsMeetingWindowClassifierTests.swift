import XCTest
@testable import TeamsAutoRecorder

final class TeamsMeetingWindowClassifierTests: XCTestCase {
    func testReturnsTrueWhenAllRequiredKeywordsExistAcrossTitles() {
        XCTAssertTrue(
            TeamsMeetingWindowClassifier.allKeywordsExist(in: ["退出", "共有", "マイク", "カメラ"])
        )
    }

    func testReturnsFalseWhenAnyRequiredKeywordIsMissing() {
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["退出", "共有", "マイク"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["退出", "共有", "カメラ"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["退出", "マイク", "カメラ"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["共有", "マイク", "カメラ"]))
    }

    func testReturnsFalseForNormalTeamsWindowTitles() {
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["Chat | Microsoft Teams"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["Calendar | Microsoft Teams"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: ["Microsoft Teams"]))
        XCTAssertFalse(TeamsMeetingWindowClassifier.allKeywordsExist(in: [""]))
    }
}
