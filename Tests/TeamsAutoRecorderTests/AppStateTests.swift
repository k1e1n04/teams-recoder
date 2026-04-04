import XCTest
@testable import TeamsAutoRecorder

final class AppStateTests: XCTestCase {
    func testLifecycleTransitions() {
        var machine = AppStateMachine()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.startRecording(sessionID: "s1", startedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(machine.state, .recording(sessionID: "s1"))

        XCTAssertTrue(machine.startTranscription())
        XCTAssertEqual(machine.state, .transcribing(sessionID: "s1"))

        XCTAssertTrue(machine.finish(transcriptPath: "/tmp/s1.txt"))
        XCTAssertEqual(machine.state, .completed(sessionID: "s1", transcriptPath: "/tmp/s1.txt"))
    }
}
