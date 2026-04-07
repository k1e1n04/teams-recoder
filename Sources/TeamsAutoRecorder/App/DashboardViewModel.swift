import Combine
import Foundation

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var displayedSessions: [SessionRecord] = []
    @Published public private(set) var isSearchActive: Bool = false
    @Published public var searchQuery: String = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var mcpServerEnabled: Bool
    public var mcpServerPort: Int { mcpServerController?.port ?? 3456 }

    private let sessionProvider: SessionListing
    private let sessionDeleter: SessionDeleting?
    private let sessionRenamer: SessionRenaming?
    private let sessionSearcher: SessionSearching?
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let mcpServerController: MCPServerControlling?
    private let summaryStore: SummaryStore?

    public init(
        sessionProvider: SessionListing,
        sessionDeleter: SessionDeleting? = nil,
        sessionRenamer: SessionRenaming? = nil,
        sessionSearcher: SessionSearching? = nil,
        launchAtLoginManager: LaunchAtLoginManaging,
        mcpServerController: MCPServerControlling? = nil,
        summaryStore: SummaryStore? = nil
    ) {
        self.sessionProvider = sessionProvider
        self.sessionDeleter = sessionDeleter
        self.sessionRenamer = sessionRenamer
        self.sessionSearcher = sessionSearcher
        self.launchAtLoginManager = launchAtLoginManager
        self.mcpServerController = mcpServerController
        self.summaryStore = summaryStore
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.mcpServerEnabled = mcpServerController?.isRunning ?? false
    }

    public func readSummary(sessionID: String) -> String? {
        return try? summaryStore?.readSession(sessionID: sessionID)
    }

    public func loadSessions(limit: Int = 100) {
        do {
            sessions = try sessionProvider.fetchRecentSessions(limit: limit)
            displayedSessions = sessions
            errorMessage = nil
        } catch {
            sessions = []
            displayedSessions = []
            errorMessage = "会議一覧の読み込みに失敗しました: \(error)"
        }
    }

    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clearSearch(); return }
        do {
            displayedSessions = try sessionSearcher?.searchSessions(query: trimmed) ?? []
            isSearchActive = true
            errorMessage = nil
        } catch {
            errorMessage = "検索に失敗しました: \(error)"
        }
    }

    public func clearSearch() {
        displayedSessions = sessions
        isSearchActive = false
    }

    public func renameSession(sessionID: String, name: String?) {
        do {
            try sessionRenamer?.renameSession(sessionID: sessionID, name: name)
            if let index = sessions.firstIndex(where: { $0.sessionID == sessionID }) {
                sessions[index].name = name
            }
            if let index = displayedSessions.firstIndex(where: { $0.sessionID == sessionID }) {
                displayedSessions[index].name = name
            }
            errorMessage = nil
        } catch {
            errorMessage = "セッション名の変更に失敗しました: \(error)"
        }
    }

    public func deleteSession(sessionID: String) {
        do {
            try sessionDeleter?.deleteSession(sessionID: sessionID)
            sessions.removeAll { $0.sessionID == sessionID }
            displayedSessions.removeAll { $0.sessionID == sessionID }
            errorMessage = nil
        } catch {
            errorMessage = "セッションの削除に失敗しました: \(error)"
        }
    }

    public func setMCPServerEnabled(_ enabled: Bool) {
        guard let controller = mcpServerController else { return }
        if enabled {
            do {
                try controller.start()
                mcpServerEnabled = controller.isRunning
                UserDefaults.standard.set(true, forKey: "mcpServerEnabled")
                errorMessage = nil
            } catch {
                mcpServerEnabled = false
                errorMessage = "MCP サーバーの起動に失敗しました: \(error)"
            }
        } else {
            controller.stop()
            mcpServerEnabled = false
            UserDefaults.standard.set(false, forKey: "mcpServerEnabled")
            errorMessage = nil
        }
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            errorMessage = nil
        } catch {
            launchAtLoginEnabled = launchAtLoginManager.isEnabled
            errorMessage = "ログイン時起動の設定に失敗しました: \(error)"
        }
    }
}
