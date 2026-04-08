import XCTest
@testable import TeamsAutoRecorder

@MainActor
final class TranscriptionQueueTests: XCTestCase {
    private func makeRepo() throws -> SessionRepository {
        let db = try Database(path: ":memory:")
        try db.migrate()
        return SessionRepository(database: db, fileManager: .default, artifactStore: nil)
    }

    func testEnqueueFiresOnQueueChangedWithCount() async throws {
        let worker = TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0)
        let repo = try makeRepo()
        let queue = TranscriptionQueue(worker: worker, repository: repo, artifactStore: nil)

        var receivedCounts: [Int] = []
        await queue.setOnQueueChanged { count in receivedCounts.append(count) }

        let exp = expectation(description: "job completed")
        await queue.setOnJobCompleted { _, _ in exp.fulfill() }

        await queue.enqueue(TranscriptionQueue.Job(
            sessionID: "s1",
            audioURL: URL(fileURLWithPath: "/tmp/audio.raw"),
            startedAt: 0,
            endedAt: 1
        ))

        await fulfillment(of: [exp], timeout: 5)
        XCTAssertTrue(receivedCounts.contains(1), "count 1 should fire on enqueue")
        XCTAssertEqual(receivedCounts.last, 0, "count 0 should fire when queue drains")
    }

    func testJobSavesSessionToRepository() async throws {
        let worker = TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0)
        let repo = try makeRepo()
        let queue = TranscriptionQueue(worker: worker, repository: repo, artifactStore: nil)

        let exp = expectation(description: "job completed")
        await queue.setOnJobCompleted { _, _ in exp.fulfill() }

        await queue.enqueue(TranscriptionQueue.Job(
            sessionID: "s1",
            audioURL: URL(fileURLWithPath: "/tmp/audio.raw"),
            startedAt: 100,
            endedAt: 200
        ))

        await fulfillment(of: [exp], timeout: 5)
        let saved = try repo.fetchSession(sessionID: "s1")
        XCTAssertEqual(saved?.sessionID, "s1")
        XCTAssertEqual(saved?.transcriptText, "stub transcript")
        XCTAssertEqual(saved?.startedAt, 100)
        XCTAssertEqual(saved?.endedAt, 200)
    }

    func testFailedTranscriptionSavesSessionWithErrorText() async throws {
        let worker = TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 1), maxRetries: 0)
        let repo = try makeRepo()
        let queue = TranscriptionQueue(worker: worker, repository: repo, artifactStore: nil)

        var completedSuccessFlag: Bool?
        let exp = expectation(description: "job completed")
        await queue.setOnJobCompleted { _, success in
            completedSuccessFlag = success
            exp.fulfill()
        }

        await queue.enqueue(TranscriptionQueue.Job(
            sessionID: "s1",
            audioURL: URL(fileURLWithPath: "/tmp/audio.raw"),
            startedAt: 0,
            endedAt: 1
        ))

        await fulfillment(of: [exp], timeout: 5)
        XCTAssertEqual(completedSuccessFlag, false)
        let saved = try repo.fetchSession(sessionID: "s1")
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved?.transcriptText.contains("[transcription failed]") == true)
    }

    func testMultipleJobsAllSaved() async throws {
        let worker = TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0)
        let repo = try makeRepo()
        let queue = TranscriptionQueue(worker: worker, repository: repo, artifactStore: nil)

        var completed: [String] = []
        let exp = expectation(description: "2 jobs completed")
        exp.expectedFulfillmentCount = 2
        await queue.setOnJobCompleted { sessionID, _ in
            completed.append(sessionID)
            exp.fulfill()
        }

        await queue.enqueue(TranscriptionQueue.Job(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/a.raw"), startedAt: 0, endedAt: 1))
        await queue.enqueue(TranscriptionQueue.Job(sessionID: "s2", audioURL: URL(fileURLWithPath: "/tmp/b.raw"), startedAt: 1, endedAt: 2))

        await fulfillment(of: [exp], timeout: 10)
        XCTAssertEqual(completed.sorted(), ["s1", "s2"])
        XCTAssertNotNil(try repo.fetchSession(sessionID: "s1"))
        XCTAssertNotNil(try repo.fetchSession(sessionID: "s2"))
    }
}
