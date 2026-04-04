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
