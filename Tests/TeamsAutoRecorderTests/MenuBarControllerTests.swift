import XCTest
@testable import TeamsAutoRecorder

final class MenuBarControllerTests: XCTestCase {
    func testUpdatesStatusAndSendsSilentNotificationOnStart() {
        let sink = NotificationSinkSpy()
        let controller = MenuBarController(notificationSink: sink)

        controller.render(state: .idle)
        XCTAssertEqual(controller.statusText, "待機中")

        controller.render(state: .recording(sessionID: "s1"))
        XCTAssertEqual(controller.statusText, "録音中")
        XCTAssertEqual(sink.messages, ["Teams 会議を検知して録音を開始しました"])
    }
}
