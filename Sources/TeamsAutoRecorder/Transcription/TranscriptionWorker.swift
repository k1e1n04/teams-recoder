import Foundation

public struct TranscriptionJob: Equatable {
    public let sessionID: String
    public let audioURL: URL

    public init(sessionID: String, audioURL: URL) {
        self.sessionID = sessionID
        self.audioURL = audioURL
    }
}

public struct TranscriptionFailure: Equatable {
    public let attempts: Int
    public let description: String
}

public enum TranscriptionResult: Equatable {
    case success(TranscriptOutput)
    case failure(TranscriptionFailure)
}

public struct TranscriptionWorker {
    private let transcriber: AudioTranscribing
    private let maxRetries: Int

    public init(transcriber: AudioTranscribing, maxRetries: Int = 1) {
        self.transcriber = transcriber
        self.maxRetries = maxRetries
    }

    public func run(job: TranscriptionJob) -> TranscriptionResult {
        let totalAttempts = maxRetries + 1
        for attempt in 1...totalAttempts {
            do {
                let output = try transcriber.transcribe(sessionID: job.sessionID, audioURL: job.audioURL)
                return .success(output)
            } catch {
                if attempt == totalAttempts {
                    return .failure(.init(attempts: totalAttempts, description: String(describing: error)))
                }
            }
        }

        return .failure(.init(attempts: totalAttempts, description: "unknown"))
    }
}
