import XCTest
@testable import TeamsAutoRecorder

final class RecorderRuntimeTests: XCTestCase {
    @MainActor
    func testRunIterationTreatsWindowAsAudioWhenMeetingUIIsActive() async {
        let now = Date(timeIntervalSince1970: 1234)
        let window = StubWindowProvider(value: true)
        let audio = StubAudioProvider(value: false)

        var captured: (Bool, Bool, Date)?
        let runtime = RecorderRuntime(
            windowSignalProvider: window,
            audioSignalProvider: audio,
            tickHandler: { windowActive, audioActive, at in
                captured = (windowActive, audioActive, at)
                return .started(sessionID: "s1")
            }
        )

        let event = await runtime.runIteration(at: now)

        XCTAssertEqual(event, .started(sessionID: "s1"))
        XCTAssertEqual(captured?.0, true)
        XCTAssertEqual(captured?.1, true)
        XCTAssertEqual(captured?.2, now)
    }
}

private final class StubWindowProvider: TeamsWindowSignalProviding {
    private let value: Bool

    init(value: Bool) { self.value = value }

    func isMeetingWindowActive(at _: Date) -> Bool { value }
}

private final class StubAudioProvider: TeamsAudioSignalProviding {
    private let value: Bool

    init(value: Bool) { self.value = value }

    func isAudioActive(at _: Date) -> Bool { value }
}
