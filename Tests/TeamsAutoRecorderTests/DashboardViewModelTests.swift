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

    func testSearchUpdatesDisplayedSessionsAndSetsIsSearchActive() {
        let provider = SessionProviderStub(sessions: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello"),
            .init(sessionID: "s2", startedAt: 3, endedAt: 4, transcriptText: "world")
        ])
        let searcher = SessionSearcherStub(results: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        ])
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(
            sessionProvider: provider,
            sessionSearcher: searcher,
            launchAtLoginManager: launch
        )
        vm.loadSessions()

        vm.search(query: "hello")

        XCTAssertEqual(vm.displayedSessions.map(\.sessionID), ["s1"])
        XCTAssertTrue(vm.isSearchActive)
        XCTAssertNil(vm.errorMessage)
    }

    func testClearSearchRestoresDisplayedSessionsAndClearsFlag() {
        let provider = SessionProviderStub(sessions: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello"),
            .init(sessionID: "s2", startedAt: 3, endedAt: 4, transcriptText: "world")
        ])
        let searcher = SessionSearcherStub(results: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        ])
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(
            sessionProvider: provider,
            sessionSearcher: searcher,
            launchAtLoginManager: launch
        )
        vm.loadSessions()
        vm.search(query: "hello")

        vm.clearSearch()

        XCTAssertEqual(vm.displayedSessions.map(\.sessionID), ["s1", "s2"])
        XCTAssertFalse(vm.isSearchActive)
    }

    func testSearchWithEmptyQueryCallsClearSearch() {
        let provider = SessionProviderStub(sessions: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        ])
        let searcher = SessionSearcherStub(results: [])
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(
            sessionProvider: provider,
            sessionSearcher: searcher,
            launchAtLoginManager: launch
        )
        vm.loadSessions()
        vm.search(query: "hello")

        vm.search(query: "   ")

        XCTAssertEqual(vm.displayedSessions.map(\.sessionID), ["s1"])
        XCTAssertFalse(vm.isSearchActive)
    }

    func testSearchFailureSetsErrorMessage() {
        let provider = SessionProviderStub(sessions: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        ])
        let searcher = SessionSearcherStub(results: [], error: StubError.forced)
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(
            sessionProvider: provider,
            sessionSearcher: searcher,
            launchAtLoginManager: launch
        )
        vm.loadSessions()

        vm.search(query: "hello")

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage!.contains("検索に失敗しました"))
    }

    func testLoadSessionsSyncsDisplayedSessions() {
        let provider = SessionProviderStub(sessions: [
            .init(sessionID: "s1", startedAt: 1, endedAt: 2, transcriptText: "hello")
        ])
        let launch = LaunchAtLoginManagerStub()
        let vm = DashboardViewModel(sessionProvider: provider, launchAtLoginManager: launch)

        vm.loadSessions()

        XCTAssertEqual(vm.displayedSessions.map(\.sessionID), ["s1"])
        XCTAssertFalse(vm.isSearchActive)
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

private struct SessionSearcherStub: SessionSearching {
    let results: [SessionRecord]
    let error: Error?

    init(results: [SessionRecord], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func searchSessions(query: String) throws -> [SessionRecord] {
        if let error { throw error }
        return results
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
