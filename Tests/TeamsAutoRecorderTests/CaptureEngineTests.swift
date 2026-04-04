import XCTest
@testable import TeamsAutoRecorder

final class CaptureEngineTests: XCTestCase {
    func testStartStopAndChunkPersistence() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let mixer = AudioMixer()
        let engine = CaptureEngine(mixer: mixer, outputDirectory: dir)

        try engine.start(sessionID: "s1")
        try engine.appendTeams(samples: [0.2, 0.4], timestamp: 0)
        try engine.appendMic(samples: [0.1, 0.3], timestamp: 0)

        let artifact = try engine.stop()
        XCTAssertEqual(artifact.sessionID, "s1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.mixedAudioURL.path))
    }
}
