import AVFoundation
import Foundation

public enum AudioNormalizerError: Error {
    case audioNormalizationFailed(String)
}

public final class AudioNormalizer: AudioNormalizing {
    public init() {}

    public func normalize(audioURL: URL) throws -> NormalizedAudio {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioNormalizerError.audioNormalizationFailed("missing audio file")
        }

        // MVP raw format: one float sample per line.
        let body = try String(contentsOf: audioURL, encoding: .utf8)
        let samples = body
            .split(separator: "\n")
            .compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard !samples.isEmpty else {
            throw AudioNormalizerError.audioNormalizationFailed("empty or invalid audio content")
        }

        return NormalizedAudio(sampleRate: 16_000, channelCount: 1, samples: samples)
    }
}
