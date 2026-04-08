// Sources/TeamsAutoRecorder/MCPServer/MCPServerController.swift
import Foundation
import Logging
import MCP
import System

#if canImport(Darwin)
    import Darwin
#endif

// MARK: - Protocols

public protocol MCPServerControlling: AnyObject {
    var isRunning: Bool { get }
    var port: Int { get }
    func start() throws
    func stop()
}

// テスト用に MCP サーバーの生成を差し替えられるよう内部プロトコルを定義
protocol MCPServerProtocol: Sendable {
    func run(port: Int) async throws
    func shutdown()
}

public protocol MCPToolHandling: Sendable {}

extension MCPToolHandler: MCPToolHandling {}

// MARK: - Implementation

public final class DefaultMCPServerController: MCPServerControlling, @unchecked Sendable {
    public private(set) var isRunning: Bool = false
    public var port: Int {
        let stored = defaults.integer(forKey: "mcpServerPort")
        return stored == 0 ? 3456 : stored
    }

    private let toolHandler: MCPToolHandling
    private let defaults: UserDefaults
    private let serverFactory: (Int) -> MCPServerProtocol
    private var serverTask: Task<Void, Never>?

    public convenience init(toolHandler: MCPToolHandler, defaults: UserDefaults = .standard) {
        self.init(
            toolHandler: toolHandler,
            defaults: defaults,
            serverFactory: { _ in RealMCPServer(toolHandler: toolHandler) }
        )
    }

    init(
        toolHandler: MCPToolHandling,
        defaults: UserDefaults,
        serverFactory: @escaping (Int) -> MCPServerProtocol = { _ in NoOpMCPServer() }
    ) {
        self.toolHandler = toolHandler
        self.defaults = defaults
        self.serverFactory = serverFactory

        if defaults.object(forKey: "mcpServerPort") == nil {
            defaults.set(3456, forKey: "mcpServerPort")
        }
    }

    public func start() throws {
        guard !isRunning else { return }
        let server = serverFactory(port)
        isRunning = true
        serverTask = Task {
            do {
                try await server.run(port: self.port)
            } catch {
                await MainActor.run { self.isRunning = false }
            }
        }
    }

    public func stop() {
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
    }
}

// MARK: - No-op server (default factory fallback)

private struct NoOpMCPServer: MCPServerProtocol {
    func run(port: Int) async throws {}
    func shutdown() {}
}

// MARK: - Real MCP Unix Socket Server

final class RealMCPServer: MCPServerProtocol, @unchecked Sendable {
    static let socketPath = "/tmp/teams-auto-recorder-mcp.sock"

    private let toolHandler: MCPToolHandler

    init(toolHandler: MCPToolHandler) {
        self.toolHandler = toolHandler
    }

    func run(port: Int) async throws {
        let socketPath = Self.socketPath

        // 既存ソケットファイルを削除
        unlink(socketPath)

        let serverFd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw MCPServerError.socketCreationFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dest in
                dest.withMemoryRebound(to: CChar.self, capacity: 104) {
                    _ = strncpy($0, src, 103)
                }
            }
        }

        let bindResult = withUnsafePointer(to: addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverFd)
            throw MCPServerError.bindFailed(errno)
        }

        guard Darwin.listen(serverFd, 5) == 0 else {
            Darwin.close(serverFd)
            throw MCPServerError.listenFailed(errno)
        }

        // ノンブロッキングモードに設定してキャンセルに対応
        let flags = fcntl(serverFd, F_GETFL, 0)
        _ = fcntl(serverFd, F_SETFL, flags | O_NONBLOCK)

        defer {
            Darwin.close(serverFd)
            unlink(socketPath)
        }

        while !Task.isCancelled {
            let clientFd = Darwin.accept(serverFd, nil, nil)
            if clientFd < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms ポーリング
                    continue
                }
                if errno == EINTR { continue }
                break
            }

            let handler = toolHandler
            Task {
                let fd = FileDescriptor(rawValue: clientFd)
                let transport = StdioTransport(input: fd, output: fd)
                let server = Server(
                    name: "teams-auto-recorder",
                    version: "1.0.0",
                    capabilities: Server.Capabilities(tools: .init())
                )
                await handler.register(on: server)
                try? await server.start(transport: transport)
                try? fd.close()
            }
        }
    }

    func shutdown() {}
}

// MARK: - Errors

private enum MCPServerError: Error {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
}
