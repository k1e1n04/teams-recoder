import Foundation
import WhisperKit

public final class DefaultWhisperInferencer: WhisperInferencing {
    public init() {}

    public func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment] {
        let whisper = try await WhisperKit(modelFolder: modelPath.path)
        let options = DecodingOptions(
            language: "ja",
            skipSpecialTokens: true
        )
        let result = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return result.flatMap { item in
            item.segments.compactMap { segment in
                let cleaned = Self.sanitizeSegmentText(segment.text)
                guard !cleaned.isEmpty else { return nil }
                return TranscriptSegment(start: Double(segment.start), end: Double(segment.end), text: cleaned)
            }
        }
    }

    static func sanitizeSegmentText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
