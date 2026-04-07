import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SessionRecord: Codable, Equatable, Identifiable {
    public var id: String { sessionID }
    public let sessionID: String
    public let startedAt: Double
    public let endedAt: Double
    public let transcriptText: String

    public init(sessionID: String, startedAt: Double, endedAt: Double, transcriptText: String) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptText = transcriptText
    }
}

public struct TranscriptExportURLs: Equatable {
    public let text: URL
    public let json: URL
}

public final class SessionRepository {
    private let database: Database
    private let fileManager: FileManager

    public init(database: Database, fileManager: FileManager) {
        self.database = database
        self.fileManager = fileManager
    }

    public func saveSession(_ record: SessionRecord) throws {
        let sql = """
        INSERT INTO sessions (session_id, started_at, ended_at, transcript_text)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
            started_at=excluded.started_at,
            ended_at=excluded.ended_at,
            transcript_text=excluded.transcript_text;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }

        bindText(record.sessionID, to: stmt, index: 1)
        sqlite3_bind_double(stmt, 2, record.startedAt)
        sqlite3_bind_double(stmt, 3, record.endedAt)
        bindText(record.transcriptText, to: stmt, index: 4)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
        }

        try upsertTranscriptJob(sessionID: record.sessionID)
        try upsertFirstSegment(sessionID: record.sessionID, text: record.transcriptText)
    }

    public func fetchSession(sessionID: String) throws -> SessionRecord? {
        let sql = """
        SELECT session_id, started_at, ended_at, transcript_text
        FROM sessions WHERE session_id = ? LIMIT 1;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }

        bindText(sessionID, to: stmt, index: 1)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        let id = String(cString: sqlite3_column_text(stmt, 0))
        let startedAt = sqlite3_column_double(stmt, 1)
        let endedAt = sqlite3_column_double(stmt, 2)
        let text = String(cString: sqlite3_column_text(stmt, 3))
        return SessionRecord(sessionID: id, startedAt: startedAt, endedAt: endedAt, transcriptText: text)
    }

    public func fetchRecentSessions(limit: Int) throws -> [SessionRecord] {
        let sql = """
        SELECT session_id, started_at, ended_at, transcript_text
        FROM sessions
        ORDER BY started_at DESC
        LIMIT ?;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var result: [SessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let startedAt = sqlite3_column_double(stmt, 1)
            let endedAt = sqlite3_column_double(stmt, 2)
            let text = String(cString: sqlite3_column_text(stmt, 3))
            result.append(.init(sessionID: id, startedAt: startedAt, endedAt: endedAt, transcriptText: text))
        }
        return result
    }

    public func exportTranscript(sessionID: String, outputDirectory: URL) throws -> TranscriptExportURLs {
        guard let record = try fetchSession(sessionID: sessionID) else {
            throw DatabaseError.executionFailed(message: "session not found")
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let textURL = outputDirectory.appendingPathComponent("\(sessionID)-Transcript.txt")
        let jsonURL = outputDirectory.appendingPathComponent("\(sessionID)-Transcript.json")

        try record.transcriptText.write(to: textURL, atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: jsonURL)

        return TranscriptExportURLs(text: textURL, json: jsonURL)
    }

    private func upsertTranscriptJob(sessionID: String) throws {
        let sql = """
        INSERT INTO transcript_jobs (session_id, status, retry_count)
        VALUES (?, 'completed', 0)
        ON CONFLICT(session_id) DO UPDATE SET
            status='completed',
            retry_count=0;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        bindText(sessionID, to: stmt, index: 1)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
        }
    }

    private func upsertFirstSegment(sessionID: String, text: String) throws {
        let sql = """
        INSERT INTO transcript_segments (session_id, segment_index, start_sec, end_sec, text)
        VALUES (?, 0, 0, 1, ?)
        ON CONFLICT(session_id, segment_index) DO UPDATE SET
            text=excluded.text;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        bindText(sessionID, to: stmt, index: 1)
        bindText(text, to: stmt, index: 2)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        _ = value.withCString { ptr in
            sqlite3_bind_text(statement, index, ptr, -1, sqliteTransient)
        }
    }
}

public protocol SessionListing {
    func fetchRecentSessions(limit: Int) throws -> [SessionRecord]
}

extension SessionRepository: SessionListing {}
