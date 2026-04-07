// Sources/TeamsAutoRecorder/MCPServer/MCPToolHandler.swift
import Foundation
import MCP

public enum MCPToolHandlerError: Error {
    case unknownTool(String)
    case invalidArgument(String)
    case missingArgument(String)
}

public final class MCPToolHandler: Sendable {
    private let sessionFetcher: SessionFetchingByDate & Sendable
    private let summaryStore: SummaryStore

    public init(
        sessionFetcher: SessionFetchingByDate & Sendable,
        summaryStore: SummaryStore
    ) {
        self.sessionFetcher = sessionFetcher
        self.summaryStore = summaryStore
    }

    // MARK: - ツール一覧

    public var toolDefinitions: [Tool] {
        [
            Tool(
                name: "get_transcripts_by_date",
                description: "指定日付（YYYY-MM-DD）のセッション文字起こし一覧を返す",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "date": .object([
                            "type": .string("string"),
                            "description": .string("対象日付 (YYYY-MM-DD)")
                        ])
                    ]),
                    "required": .array([.string("date")])
                ])
            ),
            Tool(
                name: "get_daily_summary",
                description: "指定日付の日次サマリを返す",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "date": .object([
                            "type": .string("string"),
                            "description": .string("対象日付 (YYYY-MM-DD)")
                        ])
                    ]),
                    "required": .array([.string("date")])
                ])
            ),
            Tool(
                name: "save_daily_summary",
                description: "指定日付の日次サマリを保存する",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "date": .object([
                            "type": .string("string"),
                            "description": .string("対象日付 (YYYY-MM-DD)")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("保存するサマリ (Markdown)")
                        ])
                    ]),
                    "required": .array([.string("date"), .string("content")])
                ])
            ),
            Tool(
                name: "get_session_summary",
                description: "指定セッション ID の要約を返す",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "session_id": .object([
                            "type": .string("string"),
                            "description": .string("セッション ID")
                        ])
                    ]),
                    "required": .array([.string("session_id")])
                ])
            ),
            Tool(
                name: "save_session_summary",
                description: "指定セッション ID の要約を保存する",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "session_id": .object([
                            "type": .string("string"),
                            "description": .string("セッション ID")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("保存する要約 (Markdown)")
                        ])
                    ]),
                    "required": .array([.string("session_id"), .string("content")])
                ])
            )
        ]
    }

    // MARK: - ツール呼び出し（テスト用のシンプルな同期インターフェース）

    public func callTool(name: String, arguments: [String: String]) throws -> String {
        switch name {
        case "get_transcripts_by_date":
            return try handleGetTranscriptsByDate(arguments: arguments)
        case "get_daily_summary":
            return try handleGetDailySummary(arguments: arguments)
        case "save_daily_summary":
            return try handleSaveDailySummary(arguments: arguments)
        case "get_session_summary":
            return try handleGetSessionSummary(arguments: arguments)
        case "save_session_summary":
            return try handleSaveSessionSummary(arguments: arguments)
        default:
            throw MCPToolHandlerError.unknownTool(name)
        }
    }

    // MARK: - MCP ハンドラ登録

    public func register(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { [toolDefinitions] _ in
            ListTools.Result(tools: toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(
                    content: [.text(text: "server deallocated", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            do {
                let args = params.arguments.flatMap { Self.extractStringArguments($0) } ?? [:]
                let text = try self.callTool(name: params.name, arguments: args)
                return CallTool.Result(
                    content: [.text(text: text, annotations: nil, _meta: nil)],
                    isError: false
                )
            } catch {
                return CallTool.Result(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }
    }

    // MARK: - Private handlers

    private func handleGetTranscriptsByDate(arguments: [String: String]) throws -> String {
        guard let dateStr = arguments["date"] else {
            throw MCPToolHandlerError.missingArgument("date")
        }
        guard let date = Self.parseDate(dateStr) else {
            throw MCPToolHandlerError.invalidArgument("date must be YYYY-MM-DD, got: \(dateStr)")
        }
        let sessions = try sessionFetcher.fetchSessions(for: date)
        let dtos = sessions.map { SessionDTO(record: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dtos)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func handleGetDailySummary(arguments: [String: String]) throws -> String {
        guard let date = arguments["date"] else {
            throw MCPToolHandlerError.missingArgument("date")
        }
        return try summaryStore.readDaily(date: date) ?? "No summary for this date."
    }

    private func handleSaveDailySummary(arguments: [String: String]) throws -> String {
        guard let date = arguments["date"] else {
            throw MCPToolHandlerError.missingArgument("date")
        }
        guard let content = arguments["content"] else {
            throw MCPToolHandlerError.missingArgument("content")
        }
        try summaryStore.writeDaily(date: date, content: content)
        return "Summary saved."
    }

    private func handleGetSessionSummary(arguments: [String: String]) throws -> String {
        guard let sessionID = arguments["session_id"] else {
            throw MCPToolHandlerError.missingArgument("session_id")
        }
        return try summaryStore.readSession(sessionID: sessionID) ?? "No summary for this session."
    }

    private func handleSaveSessionSummary(arguments: [String: String]) throws -> String {
        guard let sessionID = arguments["session_id"] else {
            throw MCPToolHandlerError.missingArgument("session_id")
        }
        guard let content = arguments["content"] else {
            throw MCPToolHandlerError.missingArgument("content")
        }
        try summaryStore.writeSession(sessionID: sessionID, content: content)
        return "Summary saved."
    }

    // MARK: - Helpers

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private static func extractStringArguments(_ dict: [String: Value]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, val) in dict {
            if case let .string(str) = val {
                result[key] = str
            }
        }
        return result
    }
}

// MARK: - DTO

private struct SessionDTO: Codable {
    let session_id: String
    let started_at: String
    let ended_at: String
    let name: String?
    let transcript_text: String

    init(record: SessionRecord) {
        let iso = ISO8601DateFormatter()
        self.session_id = record.sessionID
        self.started_at = iso.string(from: Date(timeIntervalSince1970: record.startedAt))
        self.ended_at = iso.string(from: Date(timeIntervalSince1970: record.endedAt))
        self.name = record.name
        self.transcript_text = record.transcriptText
    }
}
