// Sources/TeamsAutoRecorder/MCPServer/MCPServerController.swift
import Foundation
import Logging
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix

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
            serverFactory: { port in RealMCPServer(toolHandler: toolHandler, port: port) }
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

// MARK: - Real MCP HTTP Server

final class RealMCPServer: MCPServerProtocol, @unchecked Sendable {
    private let toolHandler: MCPToolHandler
    private let targetPort: Int
    private var channel: Channel?

    init(toolHandler: MCPToolHandler, port: Int) {
        self.toolHandler = toolHandler
        self.targetPort = port
    }

    func run(port: Int) async throws {
        let handler = toolHandler

        // バリデーションなしのステートレストランスポートを使用
        // Claude Code はセッション管理を必要としないため StatelessHTTPServerTransport を採用
        let transport = StatelessHTTPServerTransport(
            validationPipeline: StandardValidationPipeline(validators: [])
        )
        let server = Server(
            name: "teams-auto-recorder",
            version: "1.0.0",
            capabilities: Server.Capabilities(tools: .init())
        )
        await handler.register(on: server)
        try await server.start(transport: transport)

        let app = MCPHTTPApp(port: port, transport: transport)
        try await app.start()
        self.channel = await app.channel
    }

    func shutdown() {
        guard let ch = channel else { return }
        Task { try? await ch.close() }
    }
}

// MARK: - Minimal NIO HTTP Server for MCP

private actor MCPHTTPApp {
    private let port: Int
    private let transport: StatelessHTTPServerTransport
    private(set) var channel: Channel?

    init(port: Int, transport: StatelessHTTPServerTransport) {
        self.port = port
        self.transport = transport
    }

    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let transport = self.transport

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(MCPHTTPHandler(transport: transport))
                }
            }

        let ch = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = ch
        try await ch.closeFuture.get()
    }
}

// MARK: - NIO Channel Handler

private final class MCPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let transport: StatelessHTTPServerTransport
    private var head: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(transport: StatelessHTTPServerTransport) {
        self.transport = transport
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var buf):
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let h = head else { return }
            let buf = bodyBuffer
            head = nil
            bodyBuffer = nil

            nonisolated(unsafe) let ctx = context
            Task { @MainActor in
                await self.process(head: h, buffer: buf, context: ctx)
            }
        }
    }

    private func process(head: HTTPRequestHead, buffer: ByteBuffer?, context: ChannelHandlerContext) async {
        let path = String(head.uri.split(separator: "?").first ?? Substring(head.uri))

        // OAuth ディスカバリエンドポイントは 404 で返す（認証不要サーバーの標準的な応答）
        if path == "/.well-known/oauth-authorization-server"
            || path == "/.well-known/oauth-protected-resource" {
            nonisolated(unsafe) let ctx = context
            ctx.eventLoop.execute {
                var respHead = HTTPResponseHead(
                    version: head.version,
                    status: .notFound
                )
                respHead.headers.add(name: "content-length", value: "0")
                ctx.write(self.wrapOutboundOut(.head(respHead)), promise: nil)
                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
            return
        }

        var headers: [String: String] = [:]
        for (name, value) in head.headers {
            headers[name] = value
        }

        let body: Data?
        if let buf = buffer, buf.readableBytes > 0,
           let bytes = buf.getBytes(at: 0, length: buf.readableBytes) {
            body = Data(bytes)
        } else {
            body = nil
        }

        let request = HTTPRequest(
            method: head.method.rawValue,
            headers: headers,
            body: body,
            path: path
        )

        let response = await transport.handleRequest(request)
        nonisolated(unsafe) let ctx = context

        let statusCode = response.statusCode
        let respHeaders = response.headers
        let bodyData = response.bodyData
        ctx.eventLoop.execute {
            var respHead = HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus(statusCode: statusCode)
            )
            for (k, v) in respHeaders { respHead.headers.add(name: k, value: v) }
            ctx.write(self.wrapOutboundOut(.head(respHead)), promise: nil)
            if let data = bodyData {
                var buf = ctx.channel.allocator.buffer(capacity: data.count)
                buf.writeBytes(data)
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
            }
            ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}
