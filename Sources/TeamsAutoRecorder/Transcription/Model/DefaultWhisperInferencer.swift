import Foundation
import WhisperKit

public final class DefaultWhisperInferencer: WhisperInferencing {
    public init() {}

    public func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment] {
        let whisper = try await WhisperKit(modelFolder: modelPath.path)
        let result = try await whisper.transcribe(audioArray: samples)
        return result.flatMap { item in
            item.segments.map { segment in
                TranscriptSegment(start: Double(segment.start), end: Double(segment.end), text: segment.text)
            }
        }
    }
}
