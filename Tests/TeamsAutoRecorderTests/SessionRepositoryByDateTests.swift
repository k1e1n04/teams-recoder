// Tests/TeamsAutoRecorderTests/SessionRepositoryByDateTests.swift
import XCTest
@testable import TeamsAutoRecorder

final class SessionRepositoryByDateTests: XCTestCase {
    private var repo: SessionRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try Database(path: dir.appendingPathComponent("app.sqlite").path)
        try db.migrate()
        repo = SessionRepository(database: db, fileManager: .default)
    }

    func testFetchSessionsForDateReturnsMatchingRecords() throws {
        // 2026-04-08 09:00 JST = 2026-04-08 00:00 UTC
        // Use a known timestamp: 2026-04-08 12:00:00 JST
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 8
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let midday = cal.date(from: comps)!

        let inRecord = SessionRecord(
            sessionID: "in",
            startedAt: midday.timeIntervalSince1970,
            endedAt: midday.timeIntervalSince1970 + 3600,
            transcriptText: "inside"
        )
        let outRecord = SessionRecord(
            sessionID: "out",
            startedAt: midday.timeIntervalSince1970 + 86400,  // 翌日
            endedAt: midday.timeIntervalSince1970 + 90000,
            transcriptText: "outside"
        )
        try repo.saveSession(inRecord)
        try repo.saveSession(outRecord)

        let targetDate = cal.startOfDay(for: midday)
        let results = try repo.fetchSessions(for: targetDate)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sessionID, "in")
    }

    func testFetchSessionsForDateReturnsEmptyWhenNoMatch() throws {
        var comps = DateComponents()
        comps.year = 2099; comps.month = 1; comps.day = 1
        let farFuture = Calendar(identifier: .gregorian).date(from: comps)!

        let results = try repo.fetchSessions(for: farFuture)
        XCTAssertTrue(results.isEmpty)
    }
}
