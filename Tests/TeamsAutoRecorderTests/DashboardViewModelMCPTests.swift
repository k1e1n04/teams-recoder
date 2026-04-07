// Tests/TeamsAutoRecorderTests/DashboardViewModelMCPTests.swift
import XCTest
@testable import TeamsAutoRecorder

@MainActor
final class DashboardViewModelMCPTests: XCTestCase {
    func testMCPServerEnabledReflectsControllerState() {
        let controller = MCPServerControllerStub(isRunning: false, port: 3456)
        let vm = makeSUT(controller: controller)
        XCTAssertFalse(vm.mcpServerEnabled)
    }

    func testSetMCPServerEnabledTrueCallsStart() {
        let controller = MCPServerControllerStub(isRunning: false, port: 3456)
        let vm = makeSUT(controller: controller)

        vm.setMCPServerEnabled(true)

        XCTAssertTrue(controller.startCalled)
        XCTAssertTrue(vm.mcpServerEnabled)
        XCTAssertNil(vm.errorMessage)
    }

    func testSetMCPServerEnabledFalseCallsStop() throws {
        let controller = MCPServerControllerStub(isRunning: true, port: 3456)
        let vm = makeSUT(controller: controller)

        vm.setMCPServerEnabled(false)

        XCTAssertTrue(controller.stopCalled)
        XCTAssertFalse(vm.mcpServerEnabled)
    }

    func testSetMCPServerEnabledStartFailureSetsErrorMessage() {
        let controller = MCPServerControllerStub(isRunning: false, port: 3456, startError: MCPStubError.forced)
        let vm = makeSUT(controller: controller)

        vm.setMCPServerEnabled(true)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.mcpServerEnabled)
    }

    func testMCPServerPortReadsFromController() {
        let controller = MCPServerControllerStub(isRunning: false, port: 9999)
        let vm = makeSUT(controller: controller)
        XCTAssertEqual(vm.mcpServerPort, 9999)
    }

    // MARK: - Helpers

    private func makeSUT(controller: MCPServerControllerStub) -> DashboardViewModel {
        DashboardViewModel(
            sessionProvider: SessionProviderStub(sessions: []),
            launchAtLoginManager: LaunchAtLoginManagerStub(),
            mcpServerController: controller
        )
    }
}

// MARK: - Stubs

private enum MCPStubError: Error {
    case forced
}

private final class MCPServerControllerStub: MCPServerControlling {
    private(set) var isRunning: Bool
    let port: Int
    private let startError: Error?
    private(set) var startCalled = false
    private(set) var stopCalled = false

    init(isRunning: Bool, port: Int, startError: Error? = nil) {
        self.isRunning = isRunning
        self.port = port
        self.startError = startError
    }

    func start() throws {
        startCalled = true
        if let error = startError { throw error }
        isRunning = true
    }

    func stop() {
        stopCalled = true
        isRunning = false
    }
}

private struct SessionProviderStub: SessionListing {
    let sessions: [SessionRecord]
    func fetchRecentSessions(limit: Int) throws -> [SessionRecord] { sessions }
}

private final class LaunchAtLoginManagerStub: LaunchAtLoginManaging {
    var isEnabled: Bool = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
