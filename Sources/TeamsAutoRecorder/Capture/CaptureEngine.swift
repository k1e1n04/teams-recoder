import Foundation
import AVFoundation
import CoreMedia
import AppKit
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

public struct CaptureArtifact: Equatable {
    public let sessionID: String
    public let mixedAudioURL: URL
}

public struct CapturedAudioSamples: Equatable {
    public let teams: [Float]
    public let mic: [Float]
    public let mixed: [Float]?

    public init(teams: [Float], mic: [Float], mixed: [Float]? = nil) {
        self.teams = teams
        self.mic = mic
        self.mixed = mixed
    }
}

public protocol LiveCaptureSession: AnyObject {
    func start() throws
    func stop() throws -> CapturedAudioSamples
}

public typealias LiveCaptureSessionFactory = (String) -> LiveCaptureSession?

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
    private let liveCaptureFactory: LiveCaptureSessionFactory
    private var currentSessionID: String?
    private var chunks: [TimeInterval: TimedChunk] = [:]
    private var liveSession: LiveCaptureSession?

    public init(mixer: AudioMixer, outputDirectory: URL) {
        self.mixer = mixer
        self.outputDirectory = outputDirectory
        self.liveCaptureFactory = { _ in
            #if canImport(ScreenCaptureKit)
            return TeamsLiveCaptureSession()
            #else
            return nil
            #endif
        }
    }

    public init(
        mixer: AudioMixer,
        outputDirectory: URL,
        liveCaptureFactory: @escaping LiveCaptureSessionFactory
    ) {
        self.mixer = mixer
        self.outputDirectory = outputDirectory
        self.liveCaptureFactory = liveCaptureFactory
    }

    public func start(sessionID: String) throws {
        guard currentSessionID == nil else {
            throw CaptureEngineError.alreadyRecording
        }

        currentSessionID = sessionID
        chunks.removeAll(keepingCapacity: true)

        if let session = liveCaptureFactory(sessionID) {
            do {
                try session.start()
                liveSession = session
            } catch {
                liveSession = nil
            }
        }
    }

    public func appendTeams(samples: [Float], timestamp: TimeInterval) throws {
        guard currentSessionID != nil else {
            throw CaptureEngineError.notRecording
        }
        guard liveSession == nil else {
            return
        }

        chunks[timestamp, default: .init()].teams = samples
    }

    public func appendMic(samples: [Float], timestamp: TimeInterval) throws {
        guard currentSessionID != nil else {
            throw CaptureEngineError.notRecording
        }
        guard liveSession == nil else {
            return
        }

        chunks[timestamp, default: .init()].mic = samples
    }

    public func stop() throws -> CaptureArtifact {
        guard let sessionID = currentSessionID else {
            throw CaptureEngineError.notRecording
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let mixedURL = outputDirectory.appendingPathComponent("\(sessionID)-mixed.raw")

        let mixedSamples: [Float]
        if let liveSession {
            let live = try liveSession.stop()
            mixedSamples = live.mixed ?? mixer.mix(teams: live.teams, mic: live.mic)
            self.liveSession = nil
        } else {
            let orderedTimestamps = chunks.keys.sorted()
            mixedSamples = orderedTimestamps.flatMap { ts in
                let chunk = chunks[ts, default: .init()]
                return mixer.mix(teams: chunk.teams, mic: chunk.mic)
            }
        }

        let body = mixedSamples.map { String(format: "%.6f", $0) }.joined(separator: "\n")
        try body.data(using: .utf8)?.write(to: mixedURL)

        currentSessionID = nil
        chunks.removeAll(keepingCapacity: true)
        return CaptureArtifact(sessionID: sessionID, mixedAudioURL: mixedURL)
    }
}

#if canImport(ScreenCaptureKit)
private final class TeamsLiveCaptureSession: NSObject, LiveCaptureSession {
    private let lock = NSLock()
    private var teamsSamples: [Float] = []
    private var micSamples: [Float] = []
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "com.k1e1n04.teams-recoder.stream-audio")
    private let streamOutput: StreamAudioOutput
    private let micEngine = AVAudioEngine()
    private let realtimeMixer = RealtimeAudioMixer(sampleRate: 16_000)

    override init() {
        streamOutput = StreamAudioOutput()
        super.init()
        streamOutput.onSamples = { [weak self] samples in
            guard let self else { return }
            self.lock.lock()
            self.teamsSamples.append(contentsOf: samples)
            self.lock.unlock()
            self.realtimeMixer.appendTeams(samples: samples)
        }
    }

    func start() throws {
        try realtimeMixer.start()
        try startMicrophoneCapture()
        do {
            try startTeamsAudioCapture()
        } catch {
            micEngine.stop()
            micEngine.inputNode.removeTap(onBus: 0)
            realtimeMixer.stopSilently()
            throw error
        }
    }

    func stop() throws -> CapturedAudioSamples {
        if let stream {
            try blockingAsync {
                try await stream.stopCapture()
            }
        }
        stream = nil
        micEngine.stop()
        micEngine.inputNode.removeTap(onBus: 0)
        let mixed = realtimeMixer.stop()

        let teams = streamOutput.takeSamples()
        lock.lock()
        let mic = micSamples
        lock.unlock()
        return CapturedAudioSamples(teams: teams, mic: mic, mixed: mixed)
    }

    private func startMicrophoneCapture() throws {
        let inputNode = micEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = Self.samples(from: buffer, targetSampleRate: 16_000)
            guard !samples.isEmpty else { return }
            self.lock.lock()
            self.micSamples.append(contentsOf: samples)
            self.lock.unlock()
            self.realtimeMixer.appendMic(samples: samples)
        }
        micEngine.prepare()
        try micEngine.start()
    }

    private func startTeamsAudioCapture() throws {
        let content: SCShareableContent = try blockingAsync {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        let candidateBundleIDs = Set(["com.microsoft.teams2", "com.microsoft.teams"])
        let teamsApps = content.applications.filter { app in
            candidateBundleIDs.contains(app.bundleIdentifier)
        }
        guard let teamsApp = teamsApps.first else {
            throw CaptureEngineError.notRecording
        }
        guard let display = content.displays.first else {
            throw CaptureEngineError.notRecording
        }

        let filter = SCContentFilter(display: display, including: [teamsApp], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: streamQueue)
        try blockingAsync {
            try await stream.startCapture()
        }
        self.stream = stream
    }

    private static func samples(from buffer: AVAudioPCMBuffer, targetSampleRate: Double) -> [Float] {
        guard let channel = buffer.floatChannelData?.pointee else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }
        let sourceRate = buffer.format.sampleRate
        if sourceRate <= 0 || abs(sourceRate - targetSampleRate) < 1 {
            return (0 ..< frameCount).map { channel[$0] }
        }

        let ratio = sourceRate / targetSampleRate
        var output: [Float] = []
        output.reserveCapacity(max(1, Int(Double(frameCount) / max(ratio, 1))))
        var index = 0.0
        while Int(index) < frameCount {
            output.append(channel[Int(index)])
            index += ratio
        }
        return output
    }
}

private final class StreamAudioOutput: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var samples: [Float] = []
    var onSamples: (([Float]) -> Void)?

    func takeSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard let pcm = Self.extractFloatSamples(from: sampleBuffer), !pcm.isEmpty else { return }
        lock.lock()
        samples.append(contentsOf: pcm)
        lock.unlock()
        onSamples?(pcm)
    }

    private static func extractFloatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        )
        guard status == noErr, let pointer, length > 0 else {
            return nil
        }
        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else {
            return nil
        }
        let typed = pointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
            Array(UnsafeBufferPointer(start: ptr, count: floatCount))
        }
        return typed
    }
}

private final class RealtimeAudioMixer {
    private let engine = AVAudioEngine()
    private let teamsNode = AVAudioPlayerNode()
    private let micNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var mixedSamples: [Float] = []

    init(sampleRate: Double) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    func start() throws {
        engine.attach(teamsNode)
        engine.attach(micNode)
        engine.connect(teamsNode, to: engine.mainMixerNode, format: format)
        engine.connect(micNode, to: engine.mainMixerNode, format: format)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let chunk = Self.samples(from: buffer)
            guard !chunk.isEmpty else { return }
            self.lock.lock()
            self.mixedSamples.append(contentsOf: chunk)
            self.lock.unlock()
        }

        engine.prepare()
        try engine.start()
        teamsNode.play()
        micNode.play()
    }

    func appendTeams(samples: [Float]) {
        enqueue(samples: samples, on: teamsNode)
    }

    func appendMic(samples: [Float]) {
        enqueue(samples: samples, on: micNode)
    }

    func stop() -> [Float] {
        teamsNode.stop()
        micNode.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return mixedSamples
    }

    func stopSilently() {
        _ = stop()
    }

    private func enqueue(samples: [Float], on node: AVAudioPlayerNode) {
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?.pointee else { return }
        for i in 0 ..< samples.count {
            channel[i] = samples[i]
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?.pointee else {
            return []
        }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return [] }
        return (0 ..< count).map { channel[$0] }
    }
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func get() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func blockingAsync<T>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = BlockingResultBox<T>()
    Task {
        do {
            box.set(.success(try await operation()))
        } catch {
            box.set(.failure(error))
        }
        semaphore.signal()
    }
    semaphore.wait()
    guard let result = box.get() else {
        throw CaptureEngineError.notRecording
    }
    return try result.get()
}
#endif
