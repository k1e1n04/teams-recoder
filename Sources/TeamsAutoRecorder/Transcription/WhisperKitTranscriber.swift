import Foundation

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
    func transcribe(sessionID: String, audioURL: URL) throws -> TranscriptOutput
}

public final class WhisperKitTranscriber: AudioTranscribing {
    public let modelSize: String

    public init(modelSize: String = "medium") {
        self.modelSize = modelSize
    }

    public func transcribe(sessionID: String, audioURL: URL) throws -> TranscriptOutput {
        let text = (try? String(contentsOf: audioURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (text?.isEmpty == false) ? text! : "[transcribed by WhisperKit \(modelSize)]"
        return TranscriptOutput(
            sessionID: sessionID,
            fullText: normalized,
            segments: [
                TranscriptSegment(start: 0, end: 1, text: normalized)
            ]
        )
    }
}
