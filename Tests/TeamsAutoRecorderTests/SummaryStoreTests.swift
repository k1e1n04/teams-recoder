// Tests/TeamsAutoRecorderTests/SummaryStoreTests.swift
import XCTest
@testable import TeamsAutoRecorder

final class SummaryStoreTests: XCTestCase {
    private var dir: URL!
    private var store: SummaryStore!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = SummaryStore(directory: dir)
    }

    // MARK: - 日次サマリ

    func testWriteAndReadDailySummary() throws {
        try store.writeDaily(date: "2026-04-08", content: "# 日次\nMTG1")
        let result = try store.readDaily(date: "2026-04-08")
        XCTAssertEqual(result, "# 日次\nMTG1")
    }

    func testReadDailyReturnsNilWhenFileAbsent() throws {
        let result = try store.readDaily(date: "2099-01-01")
        XCTAssertNil(result)
    }

    func testWriteDailyCreatesDirectoryIfNeeded() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        try store.writeDaily(date: "2026-04-08", content: "hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testWriteDailyOverwritesPreviousContent() throws {
        try store.writeDaily(date: "2026-04-08", content: "old")
        try store.writeDaily(date: "2026-04-08", content: "new")
        let result = try store.readDaily(date: "2026-04-08")
        XCTAssertEqual(result, "new")
    }

    // MARK: - セッションサマリ

    func testWriteAndReadSessionSummary() throws {
        try store.writeSession(sessionID: "abc123", content: "# セッション要約")
        let result = try store.readSession(sessionID: "abc123")
        XCTAssertEqual(result, "# セッション要約")
    }

    func testReadSessionReturnsNilWhenFileAbsent() throws {
        let result = try store.readSession(sessionID: "nonexistent")
        XCTAssertNil(result)
    }
}
