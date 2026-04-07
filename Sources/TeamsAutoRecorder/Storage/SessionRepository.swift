import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SessionRecord: Codable, Equatable, Identifiable {
    public var id: String { sessionID }
    public let sessionID: String
    public let startedAt: Double
    public let endedAt: Double
    public let transcriptText: String
    public let failureStage: TranscriptionFailureStage?
    public let failureReason: String?
    public var name: String?

    public init(
        sessionID: String,
        startedAt: Double,
        endedAt: Double,
        transcriptText: String,
        failureStage: TranscriptionFailureStage? = nil,
        failureReason: String? = nil,
        name: String? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptText = transcriptText
        self.failureStage = failureStage
        self.failureReason = failureReason
        self.name = name
    }
}

public struct TranscriptExportURLs: Equatable {
    public let text: URL
    public let json: URL
}

public final class SessionRepository {
    private let database: Database
    private let fileManager: FileManager
    private let artifactStore: SessionAudioArtifactStore?

    public init(
        database: Database,
        fileManager: FileManager,
        artifactStore: SessionAudioArtifactStore? = nil
    ) {
        self.database = database
        self.fileManager = fileManager
        self.artifactStore = artifactStore
    }

    public func saveSession(_ record: SessionRecord) throws {
        let sql = """
        INSERT INTO sessions (session_id, started_at, ended_at, transcript_text, failure_stage, failure_reason, name)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
            started_at=excluded.started_at,
            ended_at=excluded.ended_at,
            transcript_text=excluded.transcript_text,
            failure_stage=excluded.failure_stage,
            failure_reason=excluded.failure_reason,
            name=excluded.name;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }

        bindText(record.sessionID, to: stmt, index: 1)
        sqlite3_bind_double(stmt, 2, record.startedAt)
        sqlite3_bind_double(stmt, 3, record.endedAt)
        bindText(record.transcriptText, to: stmt, index: 4)
        bindOptionalText(record.failureStage?.rawValue, to: stmt, index: 5)
        bindOptionalText(record.failureReason, to: stmt, index: 6)
        bindOptionalText(record.name, to: stmt, index: 7)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
        }

        try upsertTranscriptJob(sessionID: record.sessionID)
        try upsertFirstSegment(sessionID: record.sessionID, text: record.transcriptText)
    }

    public func fetchSession(sessionID: String) throws -> SessionRecord? {
        let sql = """
        SELECT session_id, started_at, ended_at, transcript_text, failure_stage, failure_reason, name
        FROM sessions WHERE session_id = ? LIMIT 1;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }

        bindText(sessionID, to: stmt, index: 1)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return rowToRecord(stmt)
    }

    public func fetchRecentSessions(limit: Int) throws -> [SessionRecord] {
        let sql = """
        SELECT session_id, started_at, ended_at, transcript_text, failure_stage, failure_reason, name
        FROM sessions
        ORDER BY started_at DESC
        LIMIT ?;
        """

        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var result: [SessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(rowToRecord(stmt))
        }
        return result
    }

    private func rowToRecord(_ stmt: OpaquePointer) -> SessionRecord {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let startedAt = sqlite3_column_double(stmt, 1)
        let endedAt = sqlite3_column_double(stmt, 2)
        let text = String(cString: sqlite3_column_text(stmt, 3))
        let failureStage: TranscriptionFailureStage? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? TranscriptionFailureStage(rawValue: String(cString: sqlite3_column_text(stmt, 4)))
            : nil
        let failureReason: String? = sqlite3_column_type(stmt, 5) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 5))
            : nil
        let name: String? = sqlite3_column_type(stmt, 6) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 6))
            : nil
        return SessionRecord(
            sessionID: id,
            startedAt: startedAt,
            endedAt: endedAt,
            transcriptText: text,
            failureStage: failureStage,
            failureReason: failureReason,
            name: name
        )
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

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            bindText(value, to: statement, index: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}

public protocol SessionListing {
    func fetchRecentSessions(limit: Int) throws -> [SessionRecord]
}

public protocol SessionDeleting {
    func deleteSession(sessionID: String) throws
}

public protocol SessionRenaming {
    func renameSession(sessionID: String, name: String?) throws
}

extension SessionRepository: SessionListing {}
extension SessionRepository: SessionRenaming {
    public func renameSession(sessionID: String, name: String?) throws {
        let sql = "UPDATE sessions SET name = ? WHERE session_id = ?;"
        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        bindOptionalText(name, to: stmt, index: 1)
        bindText(sessionID, to: stmt, index: 2)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
        }
    }
}

extension SessionRepository: SessionDeleting {
    public func deleteSession(sessionID: String) throws {
        for sql in [
            "DELETE FROM transcript_segments WHERE session_id = ?;",
            "DELETE FROM transcript_jobs WHERE session_id = ?;",
            "DELETE FROM sessions WHERE session_id = ?;"
        ] {
            let stmt = try database.prepare(sql)
            defer { database.finalize(stmt) }
            bindText(sessionID, to: stmt, index: 1)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(message: String(cString: sqlite3_errmsg(database.rawHandle)))
            }
        }
        try artifactStore?.deleteArtifact(for: sessionID)
    }
}
