import Foundation
import WhisperKit

public struct TranscriptSegment: Codable, Equatable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptOutput: Codable, Equatable {
    public let sessionID: String
    public let fullText: String
    public let segments: [TranscriptSegment]

    public init(sessionID: String, fullText: String, segments: [TranscriptSegment]) {
        self.sessionID = sessionID
        self.fullText = fullText
        self.segments = segments
    }
}

public protocol AudioTranscribing {
    func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput
}

public enum WhisperTranscriberError: Error {
    case modelLoadFailed(String)
    case inferenceFailed(String)
}

public protocol WhisperInferencing {
    func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment]
}

public final class WhisperKitTranscriber: AudioTranscribing {
    private let modelName: String
    private let modelManager: WhisperModelManaging
    private let inferencer: WhisperInferencing

    public init(
        modelName: String = "small",
        modelManager: WhisperModelManaging,
        inferencer: WhisperInferencing
    ) {
        self.modelName = modelName
        self.modelManager = modelManager
        self.inferencer = inferencer
    }

    public func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput {
        let modelURL: URL
        do {
            modelURL = try await modelManager.resolveModel(named: modelName)
        } catch {
            throw WhisperTranscriberError.modelLoadFailed(String(describing: error))
        }

        do {
            let segments = try await inferencer.transcribe(audioURL: audioURL, modelPath: modelURL)
            let fullText = segments
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TranscriptOutput(sessionID: sessionID, fullText: fullText, segments: segments)
        } catch {
            throw WhisperTranscriberError.inferenceFailed(String(describing: error))
        }
    }
}
