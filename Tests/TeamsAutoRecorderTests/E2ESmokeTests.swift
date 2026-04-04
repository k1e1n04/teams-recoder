import XCTest
@testable import TeamsAutoRecorder

final class E2ESmokeTests: XCTestCase {
    func testDetectionToTranscriptionFlow() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let db = try Database(path: temp.appendingPathComponent("e2e.sqlite").path)
        try db.migrate()

        let orchestrator = RecorderOrchestrator(
            detector: MeetingDetector(config: .forTests),
            captureEngine: CaptureEngine(mixer: AudioMixer(), outputDirectory: temp),
            worker: TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0),
            repository: SessionRepository(database: db, fileManager: .default)
        )

        let start = Date(timeIntervalSince1970: 0)
        let events: [MeetingDetectorEvent?] = [
            orchestrator.tick(windowActive: true, audioActive: true, now: start),
            orchestrator.tick(windowActive: true, audioActive: true, now: start.addingTimeInterval(1)),
            orchestrator.tick(windowActive: false, audioActive: false, now: start.addingTimeInterval(2))
        ]

        XCTAssertTrue(events.contains(.started(sessionID: "session-1")))
        XCTAssertTrue(events.contains(.stopped(sessionID: "session-1")))

        let saved = try orchestrator.repository.fetchSession(sessionID: "session-1")
        XCTAssertEqual(saved?.sessionID, "session-1")
        XCTAssertEqual(saved?.transcriptText, "stub transcript")
    }
}
