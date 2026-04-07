import AVFoundation
import Foundation
import WhisperKit

public final class DefaultWhisperInferencer: WhisperInferencing {
    public init() {}

    public func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment] {
        let whisper = try await WhisperKit(modelFolder: modelPath.path)
        let options = DecodingOptions(language: "ja", skipSpecialTokens: true)

        let chunker = AudioChunker()
        let chunkInfos = try chunker.chunks(from: audioURL)
        guard !chunkInfos.isEmpty else { return [] }

        var chunkResults: [(info: AudioChunkInfo, segments: [TranscriptSegment])] = []
        for chunkInfo in chunkInfos {
            let result = try await whisper.transcribe(audioArray: chunkInfo.samples, decodeOptions: options)
            let segments = result.flatMap { item in
                item.segments.compactMap { segment -> TranscriptSegment? in
                    let cleaned = Self.sanitizeSegmentText(segment.text)
                    guard !cleaned.isEmpty else { return nil }
                    return TranscriptSegment(
                        start: Double(segment.start),
                        end: Double(segment.end),
                        text: cleaned
                    )
                }
            }
            chunkResults.append((info: chunkInfo, segments: segments))
        }

        return AudioChunker.mergeSegments(
            chunks: chunkResults,
            overlapSeconds: chunker.overlapSeconds
        )
    }

    static func sanitizeSegmentText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
