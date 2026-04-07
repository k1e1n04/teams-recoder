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

    func testRenameSessionPersistsName() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        let repo = SessionRepository(database: db, fileManager: .default)

        let record = SessionRecord(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        try repo.saveSession(record)
        try repo.renameSession(sessionID: "s1", name: "週次定例")

        let fetched = try repo.fetchSession(sessionID: "s1")
        XCTAssertEqual(fetched?.name, "週次定例")
    }

    func testRenameSessionWithNilClearsName() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        let repo = SessionRepository(database: db, fileManager: .default)

        let record = SessionRecord(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        try repo.saveSession(record)
        try repo.renameSession(sessionID: "s1", name: "一時名")
        try repo.renameSession(sessionID: "s1", name: nil)

        let fetched = try repo.fetchSession(sessionID: "s1")
        XCTAssertNil(fetched?.name)
    }

    func testFetchSessionWithoutNameReturnsNilName() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        let repo = SessionRepository(database: db, fileManager: .default)

        try repo.saveSession(.init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hi"))

        let fetched = try repo.fetchSession(sessionID: "s1")
        XCTAssertNil(fetched?.name)
    }

    func testFetchRecentSessionsReturnsStartedAtDescending() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        let repo = SessionRepository(database: db, fileManager: .default)

        try repo.saveSession(.init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "one"))
        try repo.saveSession(.init(sessionID: "s2", startedAt: 3, endedAt: 4, transcriptText: "two"))
        try repo.saveSession(.init(sessionID: "s3", startedAt: 2, endedAt: 3, transcriptText: "three"))

        let sessions = try repo.fetchRecentSessions(limit: 3)
        XCTAssertEqual(sessions.map(\.sessionID), ["s2", "s3", "s1"])
    }
}
