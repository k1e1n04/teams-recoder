import Foundation
import SQLite3

public enum DatabaseError: Error {
    case openFailed
    case executionFailed(message: String)
    case prepareFailed(message: String)
}

public final class Database {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw DatabaseError.openFailed
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    public func migrate() throws {
        try execute(sql: """
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            started_at REAL NOT NULL,
            ended_at REAL NOT NULL,
            transcript_text TEXT NOT NULL
        );
        """)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_jobs (
            session_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            retry_count INTEGER NOT NULL
        );
        """)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_segments (
            session_id TEXT NOT NULL,
            segment_index INTEGER NOT NULL,
            start_sec REAL NOT NULL,
            end_sec REAL NOT NULL,
            text TEXT NOT NULL,
            PRIMARY KEY (session_id, segment_index)
        );
        """)

        // Migration: add name column if it doesn't exist yet
        try? execute(sql: "ALTER TABLE sessions ADD COLUMN name TEXT;")
    }

    public func execute(sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.executionFailed(message: msg)
        }
    }

    public func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(message: msg)
        }

        return statement
    }

    public func finalize(_ statement: OpaquePointer?) {
        sqlite3_finalize(statement)
    }

    public var rawHandle: OpaquePointer? {
        handle
    }
}
