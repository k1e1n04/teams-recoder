import XCTest
@testable import TeamsAutoRecorder

final class E2ESmokeTests: XCTestCase {
    func testDetectionToTranscriptionFlow() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let db = try Database(path: temp.appendingPathComponent("e2e.sqlite").path)
        try db.migrate()
        let artifactStore = SessionAudioArtifactStore(directory: temp)

        let orchestrator = RecorderOrchestrator(
            detector: MeetingDetector(config: .forTests),
            captureEngine: CaptureEngine(
                mixer: AudioMixer(),
                outputDirectory: temp,
                liveCaptureFactory: { _ in nil }
            ),
            worker: TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0),
            repository: SessionRepository(database: db, fileManager: .default, artifactStore: artifactStore),
            artifactStore: artifactStore
        )

        let start = Date(timeIntervalSince1970: 0)
        let events: [MeetingDetectorEvent?] = [
            await orchestrator.tick(windowActive: true, audioActive: true, now: start),
            await orchestrator.tick(windowActive: true, audioActive: true, now: start.addingTimeInterval(1)),
            await orchestrator.tick(windowActive: false, audioActive: false, now: start.addingTimeInterval(2))
        ]

        XCTAssertTrue(events.contains(.started(sessionID: "session-0")))
        XCTAssertTrue(events.contains(.stopped(sessionID: "session-0")))

        try await Task.sleep(nanoseconds: 200_000_000)

        let saved = try orchestrator.repository.fetchSession(sessionID: "session-0")
        XCTAssertEqual(saved?.sessionID, "session-0")
        XCTAssertEqual(saved?.transcriptText, "stub transcript")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.raw").path))
    }

    func testSavesSessionEvenWhenTranscriptionFails() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let db = try Database(path: temp.appendingPathComponent("e2e.sqlite").path)
        try db.migrate()
        let artifactStore = SessionAudioArtifactStore(directory: temp)

        let orchestrator = RecorderOrchestrator(
            detector: MeetingDetector(config: .forTests),
            captureEngine: CaptureEngine(
                mixer: AudioMixer(),
                outputDirectory: temp,
                liveCaptureFactory: { _ in nil }
            ),
            worker: TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 1), maxRetries: 0),
            repository: SessionRepository(database: db, fileManager: .default, artifactStore: artifactStore),
            artifactStore: artifactStore
        )

        let start = Date(timeIntervalSince1970: 0)
        _ = await orchestrator.tick(windowActive: true, audioActive: true, now: start)
        _ = await orchestrator.tick(windowActive: true, audioActive: true, now: start.addingTimeInterval(1))
        let stopEvent = await orchestrator.tick(windowActive: false, audioActive: false, now: start.addingTimeInterval(2))

        switch stopEvent {
        case let .transcriptionFailed(sessionID, _):
            XCTAssertEqual(sessionID, "session-0")
        default:
            XCTFail("expected transcriptionFailed event")
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let saved = try orchestrator.repository.fetchSession(sessionID: "session-0")
        XCTAssertEqual(saved?.sessionID, "session-0")
        XCTAssertNotNil(saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.raw").path))
    }

    func testStartFailureSurfacesAsTranscriptionFailureEvent() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let db = try Database(path: temp.appendingPathComponent("e2e.sqlite").path)
        try db.migrate()
        let artifactStore = SessionAudioArtifactStore(directory: temp)

        let session = LiveCaptureSessionStub(startResult: .failure(StubError.forced), stopResult: .success(.init(teams: [], mic: [])))
        let orchestrator = RecorderOrchestrator(
            detector: MeetingDetector(config: .forTests),
            captureEngine: CaptureEngine(
                mixer: AudioMixer(),
                outputDirectory: temp,
                liveCaptureFactory: { _ in session }
            ),
            worker: TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0),
            repository: SessionRepository(database: db, fileManager: .default, artifactStore: artifactStore),
            artifactStore: artifactStore
        )

        let event = await orchestrator.tick(
            windowActive: true,
            audioActive: true,
            now: Date(timeIntervalSince1970: 0)
        )

        switch event {
        case let .transcriptionFailed(sessionID, reason):
            XCTAssertEqual(sessionID, "session-0")
            XCTAssertFalse(reason.isEmpty)
        default:
            XCTFail("expected transcriptionFailed event")
        }
    }
}
