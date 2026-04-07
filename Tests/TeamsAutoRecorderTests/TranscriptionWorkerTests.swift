import XCTest
@testable import TeamsAutoRecorder

final class TranscriptionWorkerTests: XCTestCase {
    func testRetriesAndEventuallySucceeds() async throws {
        let stub = StubTranscriber(failuresBeforeSuccess: 1)
        let worker = TranscriptionWorker(transcriber: stub, maxRetries: 2)

        let url = URL(fileURLWithPath: "/tmp/audio.raw")
        let result = await worker.run(job: .init(sessionID: "s1", audioURL: url))

        switch result {
        case .success(let output):
            XCTAssertEqual(output.sessionID, "s1")
            XCTAssertEqual(stub.callCount, 2)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testFailsAfterExhaustingRetries() async {
        let stub = StubTranscriber(failuresBeforeSuccess: 10)
        let worker = TranscriptionWorker(transcriber: stub, maxRetries: 1)

        let url = URL(fileURLWithPath: "/tmp/audio.raw")
        let result = await worker.run(job: .init(sessionID: "s1", audioURL: url))

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.attempts, 2)
        }
    }

    func testPreservesStructuredFailureStage() async {
        let worker = TranscriptionWorker(transcriber: StageFailingTranscriber(), maxRetries: 0)

        let result = await worker.run(job: .init(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.raw")))

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.attempts, 1)
            XCTAssertEqual(error.stage, .modelResolve)
            XCTAssertEqual(error.description, "model missing")
        }
    }
}

private struct StageFailingTranscriber: AudioTranscribing {
    func transcribe(sessionID _: String, audioURL _: URL) async throws -> TranscriptOutput {
        throw WhisperTranscriberError.modelLoadFailed("model missing")
    }
}
