import Foundation

public struct TranscriptionJob: Equatable {
    public let sessionID: String
    public let audioURL: URL

    public init(sessionID: String, audioURL: URL) {
        self.sessionID = sessionID
        self.audioURL = audioURL
    }
}

public enum TranscriptionFailureStage: String, Codable, Equatable {
    case unknown
    case captureFinalize
    case modelResolve
    case audioNormalize
    case whisperInfer
    case sessionSave
}

public struct TranscriptionFailure: Equatable {
    public let attempts: Int
    public let stage: TranscriptionFailureStage
    public let description: String

    public init(attempts: Int, stage: TranscriptionFailureStage, description: String) {
        self.attempts = attempts
        self.stage = stage
        self.description = description
    }
}

public enum TranscriptionResult: Equatable {
    case success(TranscriptOutput)
    case failure(TranscriptionFailure)
}

public struct TranscriptionWorker: @unchecked Sendable {
    private let transcriber: AudioTranscribing
    private let maxRetries: Int

    public init(transcriber: AudioTranscribing, maxRetries: Int = 1) {
        self.transcriber = transcriber
        self.maxRetries = maxRetries
    }

    public func run(job: TranscriptionJob) async -> TranscriptionResult {
        let totalAttempts = maxRetries + 1
        for attempt in 1...totalAttempts {
            do {
                let output = try await transcriber.transcribe(sessionID: job.sessionID, audioURL: job.audioURL)
                return .success(output)
            } catch {
                if attempt == totalAttempts {
                    return .failure(Self.classify(error, attempts: totalAttempts))
                }
            }
        }

        return .failure(.init(attempts: totalAttempts, stage: .unknown, description: "unknown"))
    }

    private static func classify(_ error: Error, attempts: Int) -> TranscriptionFailure {
        switch error {
        case let WhisperTranscriberError.modelLoadFailed(description):
            return .init(attempts: attempts, stage: .modelResolve, description: description)
        case let WhisperTranscriberError.inferenceFailed(description):
            return .init(attempts: attempts, stage: .whisperInfer, description: description)
        default:
            return .init(attempts: attempts, stage: .unknown, description: String(describing: error))
        }
    }
}
