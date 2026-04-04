import XCTest
@testable import TeamsAutoRecorder

final class TranscriptionWorkerTests: XCTestCase {
    func testRetriesAndEventuallySucceeds() throws {
        let stub = StubTranscriber(failuresBeforeSuccess: 1)
        let worker = TranscriptionWorker(transcriber: stub, maxRetries: 2)

        let url = URL(fileURLWithPath: "/tmp/audio.raw")
        let result = worker.run(job: .init(sessionID: "s1", audioURL: url))

        switch result {
        case .success(let output):
            XCTAssertEqual(output.sessionID, "s1")
            XCTAssertEqual(stub.callCount, 2)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testFailsAfterExhaustingRetries() {
        let stub = StubTranscriber(failuresBeforeSuccess: 10)
        let worker = TranscriptionWorker(transcriber: stub, maxRetries: 1)

        let url = URL(fileURLWithPath: "/tmp/audio.raw")
        let result = worker.run(job: .init(sessionID: "s1", audioURL: url))

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.attempts, 2)
        }
    }
}
