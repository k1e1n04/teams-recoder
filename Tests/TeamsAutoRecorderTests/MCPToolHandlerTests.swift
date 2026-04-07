// Tests/TeamsAutoRecorderTests/MCPToolHandlerTests.swift
import XCTest
@testable import TeamsAutoRecorder

final class MCPToolHandlerTests: XCTestCase {
    private var handler: MCPToolHandler!
    private var sessionFetcher: SessionFetcherByDateStub!
    private var summaryStore: SummaryStore!
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sessionFetcher = SessionFetcherByDateStub()
        summaryStore = SummaryStore(directory: tmpDir)
        handler = MCPToolHandler(sessionFetcher: sessionFetcher, summaryStore: summaryStore)
    }

    // MARK: - get_transcripts_by_date

    func testGetTranscriptsByDateReturnsSessions() throws {
        let ts = Date(timeIntervalSince1970: 1_744_080_000) // 2026-04-08 00:00:00 UTC
        sessionFetcher.stubbedSessions = [
            SessionRecord(sessionID: "s1", startedAt: ts.timeIntervalSince1970,
                          endedAt: ts.timeIntervalSince1970 + 3600, transcriptText: "hello")
        ]
        let result = try handler.callTool(name: "get_transcripts_by_date", arguments: ["date": "2026-04-08"])
        XCTAssertTrue(result.contains("s1"))
        XCTAssertTrue(result.contains("hello"))
    }

    func testGetTranscriptsByDateEmptyReturnsEmptyArray() throws {
        sessionFetcher.stubbedSessions = []
        let result = try handler.callTool(name: "get_transcripts_by_date", arguments: ["date": "2026-04-08"])
        XCTAssertTrue(result.hasPrefix("["))
    }

    func testGetTranscriptsByDateInvalidDateThrows() {
        XCTAssertThrowsError(
            try handler.callTool(name: "get_transcripts_by_date", arguments: ["date": "not-a-date"])
        )
    }

    // MARK: - get_daily_summary

    func testGetDailySummaryReturnsSavedContent() throws {
        try summaryStore.writeDaily(date: "2026-04-08", content: "# 要約")
        let result = try handler.callTool(name: "get_daily_summary", arguments: ["date": "2026-04-08"])
        XCTAssertEqual(result, "# 要約")
    }

    func testGetDailySummaryNoFileReturnsDefaultMessage() throws {
        let result = try handler.callTool(name: "get_daily_summary", arguments: ["date": "2099-01-01"])
        XCTAssertEqual(result, "No summary for this date.")
    }

    // MARK: - save_daily_summary

    func testSaveDailySummaryPersistsAndReturnsConfirmation() throws {
        let result = try handler.callTool(
            name: "save_daily_summary",
            arguments: ["date": "2026-04-08", "content": "# MTG1"]
        )
        XCTAssertEqual(result, "Summary saved.")
        let saved = try summaryStore.readDaily(date: "2026-04-08")
        XCTAssertEqual(saved, "# MTG1")
    }

    // MARK: - get_session_summary

    func testGetSessionSummaryReturnsSavedContent() throws {
        try summaryStore.writeSession(sessionID: "s1", content: "# セッション")
        let result = try handler.callTool(name: "get_session_summary", arguments: ["session_id": "s1"])
        XCTAssertEqual(result, "# セッション")
    }

    func testGetSessionSummaryNoFileReturnsDefaultMessage() throws {
        let result = try handler.callTool(name: "get_session_summary", arguments: ["session_id": "nonexistent"])
        XCTAssertEqual(result, "No summary for this session.")
    }

    // MARK: - save_session_summary

    func testSaveSessionSummaryPersistsAndReturnsConfirmation() throws {
        let result = try handler.callTool(
            name: "save_session_summary",
            arguments: ["session_id": "s1", "content": "# セッション要約"]
        )
        XCTAssertEqual(result, "Summary saved.")
        let saved = try summaryStore.readSession(sessionID: "s1")
        XCTAssertEqual(saved, "# セッション要約")
    }

    // MARK: - unknown tool

    func testUnknownToolThrows() {
        XCTAssertThrowsError(
            try handler.callTool(name: "unknown_tool", arguments: [:])
        )
    }
}

// MARK: - Stub

private final class SessionFetcherByDateStub: SessionFetchingByDate, @unchecked Sendable {
    var stubbedSessions: [SessionRecord] = []
    var stubbedError: Error?

    func fetchSessions(for date: Date) throws -> [SessionRecord] {
        if let error = stubbedError { throw error }
        return stubbedSessions
    }
}
