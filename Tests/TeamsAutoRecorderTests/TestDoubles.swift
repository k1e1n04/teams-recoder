import Foundation
@testable import TeamsAutoRecorder

final class MockPermissionChecker: PermissionChecking {
    private let screen: Bool
    private let mic: Bool
    private(set) var openSettingsCallCount = 0

    init(screen: Bool, mic: Bool) {
        self.screen = screen
        self.mic = mic
    }

    func hasScreenRecordingPermission() -> Bool { screen }
    func hasMicrophonePermission() -> Bool { mic }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

enum StubError: Error {
    case forced
}

final class StubTranscriber: AudioTranscribing {
    private let failuresBeforeSuccess: Int
    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func transcribe(sessionID: String, audioURL: URL) throws -> TranscriptOutput {
        callCount += 1
        if callCount <= failuresBeforeSuccess {
            throw StubError.forced
        }

        return TranscriptOutput(
            sessionID: sessionID,
            fullText: "stub transcript",
            segments: [TranscriptSegment(start: 0, end: 1, text: "stub transcript")]
        )
    }
}

final class NotificationSinkSpy: NotificationSink {
    private(set) var messages: [String] = []

    func sendSilent(message: String) {
        messages.append(message)
    }
}
