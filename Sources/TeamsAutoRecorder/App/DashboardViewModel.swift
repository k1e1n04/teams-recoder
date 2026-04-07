import Combine
import Foundation

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var errorMessage: String?

    private let sessionProvider: SessionListing
    private let sessionDeleter: SessionDeleting?
    private let launchAtLoginManager: LaunchAtLoginManaging

    public init(
        sessionProvider: SessionListing,
        sessionDeleter: SessionDeleting? = nil,
        launchAtLoginManager: LaunchAtLoginManaging
    ) {
        self.sessionProvider = sessionProvider
        self.sessionDeleter = sessionDeleter
        self.launchAtLoginManager = launchAtLoginManager
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
    }

    public func loadSessions(limit: Int = 100) {
        do {
            sessions = try sessionProvider.fetchRecentSessions(limit: limit)
            errorMessage = nil
        } catch {
            sessions = []
            errorMessage = "会議一覧の読み込みに失敗しました: \(error)"
        }
    }

    public func deleteSession(sessionID: String) {
        do {
            try sessionDeleter?.deleteSession(sessionID: sessionID)
            sessions.removeAll { $0.sessionID == sessionID }
            errorMessage = nil
        } catch {
            errorMessage = "セッションの削除に失敗しました: \(error)"
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
