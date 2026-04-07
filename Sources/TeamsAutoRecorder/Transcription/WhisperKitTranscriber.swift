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
    case transcriptionFailed(String)
}

public protocol WhisperInferencing {
    func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment]
}

public final class WhisperKitTranscriber: AudioTranscribing {
    private let modelName: String
    private let modelManager: WhisperModelManaging
    private let normalizer: AudioNormalizing
    private let inferencer: WhisperInferencing

    public init(
        modelName: String = "small",
        modelManager: WhisperModelManaging,
        normalizer: AudioNormalizing,
        inferencer: WhisperInferencing
    ) {
        self.modelName = modelName
        self.modelManager = modelManager
        self.normalizer = normalizer
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
            let normalized = try normalizer.normalize(audioURL: audioURL)
            let segments = try await inferencer.transcribe(
                samples: normalized.samples,
                sampleRate: normalized.sampleRate,
                modelPath: modelURL
            )
            let fullText = segments
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TranscriptOutput(sessionID: sessionID, fullText: fullText, segments: segments)
        } catch {
            throw WhisperTranscriberError.transcriptionFailed(String(describing: error))
        }
    }
}
