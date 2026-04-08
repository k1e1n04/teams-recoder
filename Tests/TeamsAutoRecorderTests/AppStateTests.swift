import XCTest
@testable import TeamsAutoRecorder

final class AppStateTests: XCTestCase {
    func testLifecycleTransitions() {
        var machine = AppStateMachine()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.startRecording(sessionID: "s1", startedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(machine.state, .recording(sessionID: "s1"))

        machine.reset()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.recordingStartedAt)
    }

    func testStartRecordingFailsWhenAlreadyRecording() {
        var machine = AppStateMachine()
        XCTAssertTrue(machine.startRecording(sessionID: "s1", startedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(machine.startRecording(sessionID: "s2", startedAt: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(machine.state, .recording(sessionID: "s1"))
    }
}
