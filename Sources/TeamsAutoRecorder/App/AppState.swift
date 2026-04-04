import Foundation

public enum AppState: Equatable {
    case idle
    case recording(sessionID: String)
    case transcribing(sessionID: String)
    case completed(sessionID: String, transcriptPath: String)
}

public struct AppStateMachine {
    public private(set) var state: AppState = .idle
    public private(set) var recordingStartedAt: Date?

    public init() {}

    @discardableResult
    public mutating func startRecording(sessionID: String, startedAt: Date) -> Bool {
        guard case .idle = state else {
            return false
        }

        state = .recording(sessionID: sessionID)
        recordingStartedAt = startedAt
        return true
    }

    @discardableResult
    public mutating func startTranscription() -> Bool {
        guard case let .recording(sessionID) = state else {
            return false
        }

        state = .transcribing(sessionID: sessionID)
        return true
    }

    @discardableResult
    public mutating func finish(transcriptPath: String) -> Bool {
        guard case let .transcribing(sessionID) = state else {
            return false
        }

        state = .completed(sessionID: sessionID, transcriptPath: transcriptPath)
        return true
    }

    public mutating func reset() {
        state = .idle
        recordingStartedAt = nil
    }
}
