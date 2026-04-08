import Foundation

public enum AppState: Equatable {
    case idle
    case recording(sessionID: String)
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

    public mutating func reset() {
        state = .idle
        recordingStartedAt = nil
    }
}
