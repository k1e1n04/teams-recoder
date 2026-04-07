import XCTest
@testable import TeamsAutoRecorder

final class CaptureEngineTests: XCTestCase {
    func testStartStopAndChunkPersistence() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let mixer = AudioMixer()
        let engine = CaptureEngine(
            mixer: mixer,
            outputDirectory: dir,
            liveCaptureFactory: { _ in nil }
        )

        try engine.start(sessionID: "s1")
        try engine.appendTeams(samples: [0.2, 0.4], timestamp: 0)
        try engine.appendMic(samples: [0.1, 0.3], timestamp: 0)

        let artifact = try engine.stop()
        XCTAssertEqual(artifact.sessionID, "s1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.mixedAudioURL.path))
    }

    func testStopPrefersLiveCaptureArtifactWhenAvailable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let liveOutput = CapturedAudioSamples(teams: [0.5, 0.5], mic: [0.5, 0.5], mixed: [0.9, 0.1])
        let session = LiveCaptureSessionStub(stopResult: .success(liveOutput))
        let engine = CaptureEngine(
            mixer: AudioMixer(),
            outputDirectory: dir,
            liveCaptureFactory: { _ in session }
        )

        try engine.start(sessionID: "live-1")
        let artifact = try engine.stop()
        let body = try String(contentsOf: artifact.mixedAudioURL, encoding: .utf8)

        XCTAssertEqual(session.startCallCount, 1)
        XCTAssertEqual(session.stopCallCount, 1)
        XCTAssertEqual(body, "0.900000\n0.100000")
    }

    func testStartThrowsWhenLiveCaptureSetupFails() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let session = LiveCaptureSessionStub(startResult: .failure(StubError.forced), stopResult: .success(.init(teams: [], mic: [])))
        let engine = CaptureEngine(
            mixer: AudioMixer(),
            outputDirectory: dir,
            liveCaptureFactory: { _ in session }
        )

        XCTAssertThrowsError(try engine.start(sessionID: "live-fail"))
    }

    func testStopFallsBackToMixingLiveInputsWhenRecordedMixIsAllZero() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let liveOutput = CapturedAudioSamples(
            teams: [0.6, 0.2],
            mic: [0.2, 0.6],
            mixed: [0, 0]
        )
        let session = LiveCaptureSessionStub(stopResult: .success(liveOutput))
        let engine = CaptureEngine(
            mixer: AudioMixer(),
            outputDirectory: dir,
            liveCaptureFactory: { _ in session }
        )

        try engine.start(sessionID: "live-zero-mix")
        let artifact = try engine.stop()
        let body = try String(contentsOf: artifact.mixedAudioURL, encoding: .utf8)

        XCTAssertEqual(body, "0.400000\n0.400000")
    }
}

final class LiveCaptureSessionStub: LiveCaptureSession {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private let startResult: Result<Void, Error>
    private let stopResult: Result<CapturedAudioSamples, Error>

    init(
        startResult: Result<Void, Error> = .success(()),
        stopResult: Result<CapturedAudioSamples, Error>
    ) {
        self.startResult = startResult
        self.stopResult = stopResult
    }

    func start() throws {
        startCallCount += 1
        try startResult.get()
    }

    func stop() throws -> CapturedAudioSamples {
        stopCallCount += 1
        return try stopResult.get()
    }
}
