import Foundation

public struct CaptureArtifact: Equatable {
    public let sessionID: String
    public let mixedAudioURL: URL
}

public enum CaptureEngineError: Error {
    case alreadyRecording
    case notRecording
}

public final class CaptureEngine {
    private struct TimedChunk {
        var teams: [Float] = []
        var mic: [Float] = []
    }

    private let mixer: AudioMixer
    private let outputDirectory: URL
    private var currentSessionID: String?
    private var chunks: [TimeInterval: TimedChunk] = [:]

    public init(mixer: AudioMixer, outputDirectory: URL) {
        self.mixer = mixer
        self.outputDirectory = outputDirectory
    }

    public func start(sessionID: String) throws {
        guard currentSessionID == nil else {
            throw CaptureEngineError.alreadyRecording
        }

        currentSessionID = sessionID
        chunks.removeAll(keepingCapacity: true)
    }

    public func appendTeams(samples: [Float], timestamp: TimeInterval) throws {
        guard currentSessionID != nil else {
            throw CaptureEngineError.notRecording
        }

        chunks[timestamp, default: .init()].teams = samples
    }

    public func appendMic(samples: [Float], timestamp: TimeInterval) throws {
        guard currentSessionID != nil else {
            throw CaptureEngineError.notRecording
        }

        chunks[timestamp, default: .init()].mic = samples
    }

    public func stop() throws -> CaptureArtifact {
        guard let sessionID = currentSessionID else {
            throw CaptureEngineError.notRecording
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let mixedURL = outputDirectory.appendingPathComponent("\(sessionID)-mixed.raw")

        let orderedTimestamps = chunks.keys.sorted()
        let mixedSamples = orderedTimestamps.flatMap { ts in
            let chunk = chunks[ts, default: .init()]
            return mixer.mix(teams: chunk.teams, mic: chunk.mic)
        }

        let body = mixedSamples.map { String(format: "%.6f", $0) }.joined(separator: "\n")
        try body.data(using: .utf8)?.write(to: mixedURL)

        currentSessionID = nil
        chunks.removeAll(keepingCapacity: true)
        return CaptureArtifact(sessionID: sessionID, mixedAudioURL: mixedURL)
    }
}
