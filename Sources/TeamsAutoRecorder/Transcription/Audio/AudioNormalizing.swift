import Foundation

public struct NormalizedAudio {
    public let sampleRate: Double
    public let channelCount: Int
    public let samples: [Float]

    public init(sampleRate: Double, channelCount: Int, samples: [Float]) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
    }
}

public protocol AudioNormalizing {
    func normalize(audioURL: URL) throws -> NormalizedAudio
}
