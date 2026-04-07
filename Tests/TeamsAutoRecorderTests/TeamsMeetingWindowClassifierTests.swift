import XCTest
@testable import TeamsAutoRecorder

final class TeamsMeetingWindowClassifierTests: XCTestCase {
    func testReturnsTrueOnlyWhenAllRequiredKeywordsExist() {
        XCTAssertTrue(
            TeamsMeetingWindowClassifier.isMeetingWindowTitle("退出 共有 マイク カメラ")
        )
    }

    func testReturnsFalseWhenAnyRequiredKeywordIsMissing() {
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("退出 共有 マイク"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("退出 共有 カメラ"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("退出 マイク カメラ"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("共有 マイク カメラ"))
    }

    func testReturnsFalseForNormalTeamsWindowTitles() {
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("Chat | Microsoft Teams"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("Calendar | Microsoft Teams"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle("Microsoft Teams"))
        XCTAssertFalse(TeamsMeetingWindowClassifier.isMeetingWindowTitle(""))
    }
}
