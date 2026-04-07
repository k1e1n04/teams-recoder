// Tests/TeamsAutoRecorderTests/MCPServerControllerTests.swift
import XCTest
@testable import TeamsAutoRecorder

final class MCPServerControllerTests: XCTestCase {
    func testDefaultsAreNotEnabledAndPort3456() {
        let defaults = UserDefaults(suiteName: "test-mcp-\(UUID().uuidString)")!
        let controller = DefaultMCPServerController(
            toolHandler: MCPToolHandlerStub(),
            defaults: defaults
        )
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.port, 3456)
    }

    func testPortReadsFromUserDefaults() {
        let defaults = UserDefaults(suiteName: "test-mcp-\(UUID().uuidString)")!
        defaults.set(9999, forKey: "mcpServerPort")
        let controller = DefaultMCPServerController(
            toolHandler: MCPToolHandlerStub(),
            defaults: defaults
        )
        XCTAssertEqual(controller.port, 9999)
    }

    func testStartSetsIsRunningTrue() throws {
        let defaults = UserDefaults(suiteName: "test-mcp-\(UUID().uuidString)")!
        let controller = DefaultMCPServerController(
            toolHandler: MCPToolHandlerStub(),
            defaults: defaults,
            serverFactory: { _ in MCPServerStub() }
        )
        try controller.start()
        XCTAssertTrue(controller.isRunning)
    }

    func testStopSetsIsRunningFalse() throws {
        let defaults = UserDefaults(suiteName: "test-mcp-\(UUID().uuidString)")!
        let controller = DefaultMCPServerController(
            toolHandler: MCPToolHandlerStub(),
            defaults: defaults,
            serverFactory: { _ in MCPServerStub() }
        )
        try controller.start()
        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }
}

// MARK: - Stubs

private final class MCPToolHandlerStub: MCPToolHandling, Sendable {}

private final class MCPServerStub: MCPServerProtocol, Sendable {
    func run(port: Int) async throws {}
    func shutdown() {}
}
