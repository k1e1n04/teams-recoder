// Sources/TeamsAutoRecorder/MCPServer/SummaryStore.swift
import Foundation

public struct SummaryStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - 日次サマリ

    public func readDaily(date: String) throws -> String? {
        let url = directory.appendingPathComponent("daily").appendingPathComponent("\(date).md")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeDaily(date: String, content: String) throws {
        let subdir = directory.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let url = subdir.appendingPathComponent("\(date).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - セッションサマリ

    public func readSession(sessionID: String) throws -> String? {
        let url = directory.appendingPathComponent("sessions").appendingPathComponent("\(sessionID).md")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeSession(sessionID: String, content: String) throws {
        let subdir = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let url = subdir.appendingPathComponent("\(sessionID).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
