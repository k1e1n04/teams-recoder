import SwiftUI

@main
struct TeamsAutoRecorderApp: App {
    @StateObject private var viewModel = DashboardFactory.makeViewModel()
    private let notificationSink = MacOSNotificationSink()

    var body: some Scene {
        WindowGroup("TeamsAutoRecorder") {
            DashboardView(viewModel: viewModel)
                .frame(minWidth: 860, minHeight: 560)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.93, green: 0.95, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .onAppear {
                    viewModel.loadSessions()
                    notificationSink.requestAuthorizationIfNeeded()
                }
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Teams Auto Recorder")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.1, green: 0.13, blue: 0.24))

            VStack(alignment: .leading, spacing: 12) {
                Toggle("ログイン時に自動起動", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                ))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .toggleStyle(.switch)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("保存済み会議")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                if viewModel.sessions.isEmpty {
                    Text("保存済み会議はまだありません。")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                } else {
                    List(viewModel.sessions, id: \.sessionID) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.sessionID)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text(timeLabel(session: session))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(session.transcriptText)
                                .lineLimit(2)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.inset)
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(24)
    }

    private func timeLabel(session: SessionRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        let start = Date(timeIntervalSince1970: session.startedAt)
        let end = Date(timeIntervalSince1970: session.endedAt)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

private enum DashboardFactory {
    @MainActor
    static func makeViewModel() -> DashboardViewModel {
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("TeamsAutoRecorder", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let database = try Database(path: base.appendingPathComponent("teams-auto-recorder.sqlite").path)
            try database.migrate()
            let repository = SessionRepository(database: database, fileManager: .default)
            return DashboardViewModel(
                sessionProvider: repository,
                launchAtLoginManager: SystemLaunchAtLoginManager()
            )
        } catch {
            return DashboardViewModel(
                sessionProvider: FallbackSessionProvider(),
                launchAtLoginManager: FallbackLaunchAtLoginManager()
            )
        }
    }
}

private struct FallbackSessionProvider: SessionListing {
    func fetchRecentSessions(limit: Int) throws -> [SessionRecord] { [] }
}

private final class FallbackLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
