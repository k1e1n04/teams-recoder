import Combine
import Foundation

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var errorMessage: String?

    private let sessionProvider: SessionListing
    private let launchAtLoginManager: LaunchAtLoginManaging

    public init(sessionProvider: SessionListing, launchAtLoginManager: LaunchAtLoginManaging) {
        self.sessionProvider = sessionProvider
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
