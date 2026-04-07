import XCTest
@testable import TeamsAutoRecorder

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testLoadFetchesSessionsIntoViewModel() {
        let provider = SessionProviderStub(
            sessions: [
                .init(sessionID: "s2", startedAt: 2, endedAt: 3, transcriptText: "two"),
                .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "one")
            ]
        )
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(sessionProvider: provider, launchAtLoginManager: launch)

        vm.loadSessions()

        XCTAssertEqual(vm.sessions.map(\.sessionID), ["s2", "s1"])
        XCTAssertNil(vm.errorMessage)
    }

    func testRenameSessionUpdatesNameInViewModel() {
        let provider = SessionProviderStub(
            sessions: [.init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")]
        )
        let renamer = SessionRenamerStub()
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(sessionProvider: provider, sessionRenamer: renamer, launchAtLoginManager: launch)
        vm.loadSessions()

        vm.renameSession(sessionID: "s1", name: "週次定例")

        XCTAssertEqual(vm.sessions.first?.name, "週次定例")
        XCTAssertEqual(renamer.calls.count, 1)
        XCTAssertEqual(renamer.calls.first?.0, "s1")
        XCTAssertEqual(renamer.calls.first?.1, "週次定例")
        XCTAssertNil(vm.errorMessage)
    }

    func testRenameSessionFailureSetsErrorMessage() {
        let provider = SessionProviderStub(
            sessions: [.init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")]
        )
        let renamer = SessionRenamerStub(renameError: StubError.forced)
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(sessionProvider: provider, sessionRenamer: renamer, launchAtLoginManager: launch)
        vm.loadSessions()

        vm.renameSession(sessionID: "s1", name: "失敗")

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.sessions.first?.name)
    }

    func testSetLaunchAtLoginUpdatesManagerAndState() {
        let provider = SessionProviderStub(sessions: [])
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(sessionProvider: provider, launchAtLoginManager: launch)

        vm.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(launch.setEnabledCalls, [true])
        XCTAssertTrue(vm.launchAtLoginEnabled)
    }

    func testSetLaunchAtLoginFailureSetsErrorMessage() {
        let provider = SessionProviderStub(sessions: [])
        let launch = LaunchAtLoginManagerStub(setError: StubError.forced)
        let vm = DashboardViewModel(sessionProvider: provider, launchAtLoginManager: launch)

        vm.setLaunchAtLoginEnabled(true)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.launchAtLoginEnabled)
    }
}

private final class SessionRenamerStub: SessionRenaming {
    private(set) var calls: [(String, String?)] = []
    private let renameError: Error?

    init(renameError: Error? = nil) {
        self.renameError = renameError
    }

    func renameSession(sessionID: String, name: String?) throws {
        if let renameError { throw renameError }
        calls.append((sessionID, name))
    }
}

private struct SessionProviderStub: SessionListing {
    let sessions: [SessionRecord]

    func fetchRecentSessions(limit: Int) throws -> [SessionRecord] {
        Array(sessions.prefix(limit))
    }
}

private final class LaunchAtLoginManagerStub: LaunchAtLoginManaging {
    private(set) var isEnabled: Bool
    private(set) var setEnabledCalls: [Bool] = []
    private let setError: Error?

    init(isEnabled: Bool = false, setError: Error? = nil) {
        self.isEnabled = isEnabled
        self.setError = setError
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let setError {
            throw setError
        }
        isEnabled = enabled
    }
}
