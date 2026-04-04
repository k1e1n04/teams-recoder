import XCTest
@testable import TeamsAutoRecorder

final class SessionRepositoryTests: XCTestCase {
    func testSaveAndFetchSessionAndExport() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        let repo = SessionRepository(database: db, fileManager: .default)

        let record = SessionRecord(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        try repo.saveSession(record)

        let fetched = try repo.fetchSession(sessionID: "s1")
        XCTAssertEqual(fetched?.sessionID, "s1")

        let urls = try repo.exportTranscript(sessionID: "s1", outputDirectory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.text.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.json.path))
    }
}
