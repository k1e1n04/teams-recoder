import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices

// MARK: - App

@main
struct TeamsAutoRecorderApp: App {
    @StateObject private var viewModel = DashboardFactory.makeViewModel()
    private let notificationSink = MacOSNotificationSink()
    @StateObject private var runtimeController = RuntimeController()

    var body: some Scene {
        WindowGroup("Teams Auto Recorder") {
            RootView(viewModel: viewModel, runtimeController: runtimeController)
                .frame(minWidth: 920, minHeight: 580)
                .onAppear {
                    viewModel.loadSessions()
                    notificationSink.requestAuthorizationIfNeeded()
                    runtimeController.startIfNeeded(notificationSink: notificationSink) {
                        viewModel.loadSessions()
                    }
                }
        }
    }
}

// MARK: - Color Tokens

private extension Color {
    static let obsidianBase    = Color(red: 0.059, green: 0.063, blue: 0.078) // #0F1014
    static let obsidianPanel   = Color(red: 0.086, green: 0.094, blue: 0.118) // #161820
    static let obsidianSurface = Color(red: 0.122, green: 0.133, blue: 0.165) // #1F2229
    static let obsidianBorder  = Color(red: 0.165, green: 0.176, blue: 0.227) // #2A2D3A
    static let obsidianHover   = Color(red: 0.137, green: 0.149, blue: 0.188) // #232530

    static let inkPrimary   = Color(red: 0.918, green: 0.906, blue: 0.882) // #EAE7E1
    static let inkSecondary = Color(red: 0.600, green: 0.624, blue: 0.698) // #99A0B2
    static let inkMuted     = Color(red: 0.365, green: 0.384, blue: 0.455) // #5D6274
    static let inkDim       = Color(red: 0.220, green: 0.235, blue: 0.290) // #383C4A

    static let amber  = Color(red: 0.949, green: 0.647, blue: 0.188) // #F2A530
    static let recRed = Color(red: 0.910, green: 0.278, blue: 0.278) // #E84747
    static let okGreen = Color(red: 0.243, green: 0.745, blue: 0.502) // #3EBD80
}

// MARK: - Root Layout

private struct RootView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var runtimeController: RuntimeController

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel, runtimeController: runtimeController)
                .frame(width: 272)
            Rectangle()
                .fill(Color.obsidianBorder)
                .frame(width: 1)
            SessionsPanel(viewModel: viewModel)
        }
        .background(Color.obsidianBase)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var runtimeController: RuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader()
            Divider().background(Color.obsidianBorder)
            StatusSection(runtimeController: runtimeController)
            Divider().background(Color.obsidianBorder)
            ControlsSection(viewModel: viewModel, runtimeController: runtimeController)
            Spacer()
            SidebarFooter()
        }
        .background(Color.obsidianPanel)
    }
}

private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.amber.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.amber)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Teams Auto Recorder")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.inkPrimary)
                    Text("会議録音・文字起こし")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }
}

private struct StatusSection: View {
    @ObservedObject var runtimeController: RuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "現在の状態")
            StatusIndicatorView(runtimeController: runtimeController)

            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(title: "最後の結果")
                Text(runtimeController.lastResultText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        runtimeController.lastResultText.contains("失敗")
                            ? Color.recRed
                            : Color.inkSecondary
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct ControlsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var runtimeController: RuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "操作")
            RecordButton(runtimeController: runtimeController)

            LaunchToggle(
                isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                )
            )

            MCPToggleSection(viewModel: viewModel)

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.okGreen.opacity(0.7))
                .frame(width: 5, height: 5)
            Text("TAR v1.0")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkDim)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}

// MARK: - Status Indicator

private struct StatusIndicatorView: View {
    @ObservedObject var runtimeController: RuntimeController
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    private var isRecording: Bool { runtimeController.statusText.contains("録音中") }
    private var isProcessing: Bool { runtimeController.statusText.contains("文字起こし中") }
    private var isError: Bool { runtimeController.statusText.contains("権限不足") || runtimeController.statusText.contains("エラー") }

    private var dotColor: Color {
        if isRecording  { return .recRed }
        if isProcessing { return .amber  }
        if isError      { return .recRed }
        return .okGreen
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.recRed.opacity(pulseOpacity))
                        .frame(width: 28, height: 28)
                        .scaleEffect(pulseScale)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: dotColor.opacity(0.8), radius: 4)
            }
            .frame(width: 28, height: 28)

            Text(runtimeController.statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
        }
        .onAppear { animateIfNeeded() }
        .onChange(of: isRecording) { _ in animateIfNeeded() }
    }

    private func animateIfNeeded() {
        if isRecording {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulseScale = 2.4
                pulseOpacity = 0.0
            }
        } else {
            withAnimation(.default) {
                pulseScale = 1.0
                pulseOpacity = 0.6
            }
        }
    }
}

// MARK: - Record Button

private struct RecordButton: View {
    @ObservedObject var runtimeController: RuntimeController
    @State private var isHovered = false

    private var isRecording: Bool { runtimeController.isManuallyRecording }

    var body: some View {
        Button(action: { runtimeController.toggleManualRecording() }) {
            HStack(spacing: 10) {
                Image(systemName: isRecording ? "stop.fill" : "circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRecording ? Color.recRed : Color.amber)
                    .frame(width: 16)
                Text(isRecording ? "録音を停止" : "手動録音を開始")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.obsidianHover : Color.obsidianSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isRecording
                                    ? Color.recRed.opacity(0.45)
                                    : (isHovered ? Color.obsidianBorder.opacity(1.5) : Color.obsidianBorder),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Launch Toggle

private struct LaunchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                Text("ログイン時に自動起動")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            MiniToggle(isOn: $isOn)
        }
    }
}

private struct MCPToggleSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                    Text("Claude Code MCP サーバー")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                MiniToggle(
                    isOn: Binding(
                        get: { viewModel.mcpServerEnabled },
                        set: { viewModel.setMCPServerEnabled($0) }
                    )
                )
            }

            if viewModel.mcpServerEnabled {
                let url = "http://localhost:\(viewModel.mcpServerPort)/mcp"
                HStack(spacing: 6) {
                    Text(url)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
                Text("ポート変更は再起動が必要です")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.inkDim)
            }
        }
    }
}

private struct MiniToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 100)
                .fill(isOn ? Color.okGreen.opacity(0.75) : Color.obsidianBorder)
                .frame(width: 36, height: 20)
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 16, height: 16)
                .padding(.horizontal, 2)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Error Banner

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.recRed)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.recRed.opacity(0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.recRed.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.recRed.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.inkDim)
            .tracking(1.0)
            .textCase(.uppercase)
    }
}

// MARK: - Sessions Panel

private struct SessionsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedSession: SessionRecord?
    @State private var renamingSessionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionsPanelHeader(viewModel: viewModel)
            Divider().background(Color.obsidianBorder)

            if viewModel.displayedSessions.isEmpty {
                if viewModel.isSearchActive {
                    SearchEmptyStateView(query: viewModel.searchQuery)
                } else {
                    EmptySessionsView()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.displayedSessions, id: \.sessionID) { session in
                            if renamingSessionID == session.sessionID {
                                InlineRenameRow(
                                    session: session,
                                    onCommit: { newName in
                                        viewModel.renameSession(sessionID: session.sessionID, name: newName.isEmpty ? nil : newName)
                                        renamingSessionID = nil
                                    },
                                    onCancel: { renamingSessionID = nil }
                                )
                            } else {
                                SessionRowView(session: session)
                                    .onTapGesture(count: 2) { renamingSessionID = session.sessionID }
                                    .onTapGesture(count: 1) { selectedSession = session }
                            }
                            Rectangle()
                                .fill(Color.obsidianBorder.opacity(0.6))
                                .frame(height: 1)
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.obsidianBase)
        .sheet(item: $selectedSession) { session in
            SessionDetailView(
                session: session,
                onRename: { newName in
                    viewModel.renameSession(sessionID: session.sessionID, name: newName.isEmpty ? nil : newName)
                    if let idx = viewModel.displayedSessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                        selectedSession = viewModel.displayedSessions[idx]
                    }
                },
                onDelete: {
                    viewModel.deleteSession(sessionID: session.sessionID)
                    selectedSession = nil
                }
            )
        }
    }
}

private struct SessionsPanelHeader: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("会議記録")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.inkPrimary)
                    Text("録音・文字起こし済みセッション")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                let count = viewModel.displayedSessions.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.inkMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.obsidianSurface)
                        .overlay(
                            Capsule().strokeBorder(Color.obsidianBorder, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkMuted)
                TextField("検索ワードを入力…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkPrimary)
                    .onSubmit { viewModel.search(query: viewModel.searchQuery) }
                if viewModel.isSearchActive {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.obsidianSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.obsidianBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 28)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Empty State

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.inkDim)
            VStack(spacing: 6) {
                Text("記録なし")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
                Text("Teams 会議が検知されると\n自動的に録音・文字起こしを行います")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }
}

private struct SearchEmptyStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.inkDim)
            VStack(spacing: 6) {
                Text("該当なし")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
                Text("\"\(query)\" に一致するセッションが見つかりません")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.inkDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }
}

// MARK: - Inline Rename Row

private struct InlineRenameRow: View {
    let session: SessionRecord
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(session: SessionRecord, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: session.name ?? "")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .fill(Color.amber.opacity(0.9))
                .frame(width: 2.5)
                .padding(.vertical, 14)
                .padding(.leading, 28)

            VStack(alignment: .leading, spacing: 4) {
                TextField("名前を入力…", text: $text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { onCommit(text) }
                    .onExitCommand { onCancel() }
                Text(session.sessionID)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.inkDim)
                HStack(spacing: 8) {
                    Button("確定") { onCommit(text) }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.amber)
                        .buttonStyle(.plain)
                    Button("キャンセル") { onCancel() }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkMuted)
                        .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 28)
            .padding(.vertical, 14)
        }
        .background(Color.obsidianHover)
        .onAppear { focused = true }
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let session: SessionRecord
    @State private var isHovered = false

    private var isFailed: Bool {
        session.transcriptText.hasPrefix("[transcription failed]")
    }
    private var accentColor: Color { isFailed ? .recRed : .okGreen }

    private var displayText: String {
        if isFailed {
            let raw = session.transcriptText
                .replacingOccurrences(of: "[transcription failed] ", with: "")
            return TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        }
        return session.transcriptText.isEmpty ? "（文字起こしなし）" : session.transcriptText
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(accentColor.opacity(isHovered ? 1.0 : 0.7))
                .frame(width: 2.5)
                .padding(.vertical, 14)
                .padding(.leading, 28)
                .animation(.easeInOut(duration: 0.12), value: isHovered)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = session.name {
                            Text(name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.inkPrimary)
                            Text(session.sessionID)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.inkDim)
                        } else {
                            Text(session.sessionID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.amber)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentColor)
                        Text(durationLabel)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.inkMuted)
                    }
                }

                Text(dateTimeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)

                Text(displayText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isFailed ? Color.recRed.opacity(0.85) : Color.inkSecondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .padding(.leading, 14)
            .padding(.trailing, 28)
            .padding(.vertical, 14)
        }
        .background(
            isHovered ? Color.obsidianHover : Color.clear
        )
        .animation(.easeInOut(duration: 0.10), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var dateTimeLabel: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        let start = Date(timeIntervalSince1970: session.startedAt)
        let end = Date(timeIntervalSince1970: session.endedAt)
        return "\(f.string(from: start))  →  \(f.string(from: end))"
    }

    private var durationLabel: String {
        let secs = Int(max(0, session.endedAt - session.startedAt))
        guard secs > 0 else { return "—" }
        return secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
    }
}

// MARK: - Session Detail

private struct SessionDetailView: View {
    let session: SessionRecord
    let onRename: ((String) -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""

    init(session: SessionRecord, onRename: ((String) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.session = session
        self.onRename = onRename
        self.onDelete = onDelete
    }

    private var isFailed: Bool {
        session.transcriptText.hasPrefix("[transcription failed]")
    }

    private var fullText: String {
        if isFailed {
            let raw = session.transcriptText
                .replacingOccurrences(of: "[transcription failed] ", with: "")
            return TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        }
        return session.transcriptText.isEmpty ? "（文字起こしなし）" : session.transcriptText
    }

    private var dateTimeLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        let start = Date(timeIntervalSince1970: session.startedAt)
        let end = Date(timeIntervalSince1970: session.endedAt)
        return "\(f.string(from: start))  →  \(f.string(from: end))"
    }

    private var durationLabel: String {
        let secs = Int(max(0, session.endedAt - session.startedAt))
        guard secs > 0 else { return "—" }
        return secs < 60 ? "\(secs)秒" : "\(secs / 60)分 \(secs % 60)秒"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if isRenaming {
                        HStack(spacing: 8) {
                            TextField("名前を入力…", text: $renameText)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.inkPrimary)
                                .textFieldStyle(.plain)
                                .onSubmit { commitRename() }
                                .onExitCommand { isRenaming = false }
                            Button("確定") { commitRename() }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.amber)
                                .buttonStyle(.plain)
                            Button("キャンセル") { isRenaming = false }
                                .font(.system(size: 11))
                                .foregroundStyle(Color.inkMuted)
                                .buttonStyle(.plain)
                        }
                    } else if let name = session.name {
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.inkPrimary)
                        Text(session.sessionID)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.inkDim)
                    } else {
                        Text(session.sessionID)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.amber)
                    }
                    Text(dateTimeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkMuted)
                    HStack(spacing: 6) {
                        Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isFailed ? Color.recRed : Color.okGreen)
                        Text(isFailed ? "文字起こし失敗" : "完了 · \(durationLabel)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isFailed ? Color.recRed : Color.inkMuted)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    if onRename != nil && !isRenaming {
                        Button(action: { startRenaming() }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.inkSecondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("名前を変更")
                    }
                    if onDelete != nil {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.recRed.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("このセッションを削除")
                    }
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.inkDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider().background(Color.obsidianBorder)

            // Transcript body
            ScrollView {
                Text(fullText)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isFailed ? Color.recRed.opacity(0.85) : Color.inkSecondary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .background(Color.obsidianBase)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "このセッションを削除しますか？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                onDelete?()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は元に戻せません。")
        }
    }

    private func startRenaming() {
        renameText = session.name ?? ""
        isRenaming = true
    }

    private func commitRename() {
        onRename?(renameText)
        isRenaming = false
    }
}

// MARK: - Factory & Fallbacks

private enum DashboardFactory {
    @MainActor
    static func makeViewModel() -> DashboardViewModel {
        do {
            let base = try AppSupportDirectoryResolver().resolve()
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let database = try Database(path: base.appendingPathComponent("teams-auto-recorder.sqlite").path)
            try database.migrate()
            let artifactStore = SessionAudioArtifactStore(directory: base)
            try artifactStore.cleanupExpiredArtifacts()
            let repository = SessionRepository(database: database, fileManager: .default, artifactStore: artifactStore)
            let summaryStore = SummaryStore(directory: base.appendingPathComponent("summaries", isDirectory: true))
            let toolHandler = MCPToolHandler(sessionFetcher: repository, summaryStore: summaryStore)
            let mcpController = DefaultMCPServerController(toolHandler: toolHandler)
            return DashboardViewModel(
                sessionProvider: repository,
                sessionDeleter: repository,
                sessionRenamer: repository,
                sessionSearcher: repository,
                launchAtLoginManager: SystemLaunchAtLoginManager(),
                mcpServerController: mcpController
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

// MARK: - Runtime Controller

@MainActor
private final class RuntimeController: ObservableObject {
    @Published private(set) var statusText: String = "待機中"
    @Published private(set) var isManuallyRecording: Bool = false
    @Published private(set) var lastResultText: String = "まだありません"
    private let accessibilityMissingStatus = "権限不足: アクセシビリティ"

    private var runtime: RecorderRuntime?
    private var loopTask: Task<Void, Never>?
    private var onSessionSaved: (() -> Void)?
    private var notificationSink: NotificationSink?
    private var microphoneMonitor: MicrophoneLevelMonitor?
    private let accessibilityTextCollector = TeamsAccessibilityTextCollector()
    private let ocrTextCollector = TeamsWindowOCRTextCollector()
    private var hasRequestedAccessibilityTrust = false

    func startIfNeeded(notificationSink: NotificationSink, onSessionSaved: @escaping () -> Void) {
        self.onSessionSaved = onSessionSaved
        self.notificationSink = notificationSink
        guard loopTask == nil else { return }

        let permissionChecker = DefaultPermissionChecker()
        if !permissionChecker.requestScreenRecordingPermissionIfNeeded() {
            statusText = "権限不足: 画面収録"
            permissionChecker.openSystemSettings(for: [.screenRecording])
            return
        }
        requestAccessibilityTrustIfNeeded()

        switch permissionChecker.microphoneAuthorizationStatus() {
        case .authorized:
            bootstrapRuntime()
        case .notDetermined:
            statusText = "マイク権限を確認中"
            permissionChecker.requestMicrophonePermission { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.bootstrapRuntime()
                    } else {
                        self.statusText = "権限不足: マイク"
                        DefaultPermissionChecker().openSystemSettings(for: [.microphone])
                    }
                }
            }
        default:
            statusText = "権限不足: マイク"
            permissionChecker.openSystemSettings(for: [.microphone])
        }
    }

    private func bootstrapRuntime() {
        do {
            let base = try AppSupportDirectoryResolver().resolve()
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

            let orchestrator = try AppBootstrap().makeDefaultOrchestrator(storageDirectory: base)
            let teamsWindowProvider = TeamsWindowSignalProvider(holdSeconds: 8, evaluator: { _ in
                self.hasVisibleTeamsWindow()
            })
            let slackWindowProvider = TeamsWindowSignalProvider(holdSeconds: 8, evaluator: { _ in
                self.hasVisibleSlackHuddle()
            })
            let windowProvider = CompositeWindowSignalProvider(providers: [teamsWindowProvider, slackWindowProvider])
            let windowFallbackProvider = TeamsAudioSignalProvider { date in
                windowProvider.isMeetingWindowActive(at: date)
            }
            let audioProvider: TeamsAudioSignalProviding
            do {
                let monitor = try MicrophoneLevelMonitor()
                microphoneMonitor = monitor
                let micProvider = TeamsAudioSignalProvider { date in
                    monitor.isActive(at: date)
                }
                audioProvider = AudioSignalProviderFactory.make(
                    microphoneProvider: micProvider,
                    windowFallbackProvider: windowFallbackProvider
                )
            } catch {
                // If mic metering setup fails, fall back to Teams window activity.
                audioProvider = AudioSignalProviderFactory.make(
                    microphoneProvider: nil,
                    windowFallbackProvider: windowFallbackProvider
                )
            }

            runtime = RecorderRuntime(
                orchestrator: orchestrator,
                windowSignalProvider: windowProvider,
                audioSignalProvider: audioProvider
            )

            loopTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    if !self.isManuallyRecording {
                        if let event = await self.runtime?.runIteration(onTranscriptionStarted: {
                            self.statusText = "文字起こし中"
                        }) {
                            self.consume(event)
                        }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } catch {
            statusText = "起動エラー"
        }
    }

    deinit {
        loopTask?.cancel()
    }

    private func requestAccessibilityTrustIfNeeded() {
        guard !AXIsProcessTrusted(), !hasRequestedAccessibilityTrust else { return }
        hasRequestedAccessibilityTrust = true
        statusText = accessibilityMissingStatus
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func hasVisibleTeamsWindow() -> Bool {
        let candidateBundleIDs = ["com.microsoft.teams2", "com.microsoft.teams"]
        let runningApps = candidateBundleIDs
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { !$0.isTerminated }
        guard !runningApps.isEmpty else { return false }

        let accessibilityTrusted = AXIsProcessTrusted()
        guard accessibilityTrusted else {
            if statusText != accessibilityMissingStatus {
                statusText = accessibilityMissingStatus
            }
            return false
        }
        if statusText == accessibilityMissingStatus {
            statusText = "待機中"
        }
        let processIDs = Set(runningApps.map(\.processIdentifier))
        var visibleTexts = runningApps.flatMap { app in
            accessibilityTextCollector.collectTexts(for: app.processIdentifier)
        }
        if !TeamsMeetingWindowClassifier.allKeywordsExist(in: visibleTexts) {
            visibleTexts.append(contentsOf: ocrTextCollector.collectTexts(for: processIDs))
        }
        return TeamsMeetingControlEvaluator.isMeetingUIActive(
            accessibilityTrusted: accessibilityTrusted,
            visibleTexts: visibleTexts
        )
    }

    private func hasVisibleSlackHuddle() -> Bool {
        let bundleID = "com.tinyspeck.slackmacgap"
        let runningApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        guard !runningApps.isEmpty else { return false }

        guard AXIsProcessTrusted() else { return false }

        let visibleTexts = runningApps.flatMap { app in
            accessibilityTextCollector.collectTexts(for: app.processIdentifier)
        }
        return SlackHuddleWindowClassifier.allKeywordsExist(in: visibleTexts)
    }

    private func consume(_ event: MeetingDetectorEvent) {
        switch event {
        case let .started(sessionID):
            statusText = "録音中"
            notificationSink?.sendSilent(message: "Teams 会議を検知して録音を開始しました (\(sessionID))")
        case let .stopped(sessionID):
            statusText = "待機中"
            lastResultText = "保存完了 (\(sessionID))"
            onSessionSaved?()
        case let .transcriptionFailed(sessionID, reason):
            statusText = "待機中"
            let userVisibleReason = TranscriptionFailureMessageFormatter.userVisibleMessage(from: reason)
            lastResultText = "文字起こし失敗 (\(sessionID)): \(userVisibleReason)"
            notificationSink?.sendSilent(message: "文字起こし失敗: \(sessionID) \(reason)")
            onSessionSaved?()
        case .fallbackToNotifyOnly:
            statusText = "通知のみ"
        }
    }

    func toggleManualRecording() {
        if isManuallyRecording {
            isManuallyRecording = false
            statusText = "文字起こし中"
            Task { @MainActor in
                if let event = await self.runtime?.stopManualRecording() {
                    self.consume(event)
                } else {
                    self.statusText = "待機中"
                }
            }
        } else {
            do {
                try runtime?.startManualRecording()
                isManuallyRecording = true
                statusText = "録音中 (手動)"
            } catch {
                statusText = "録音開始エラー"
            }
        }
    }
}

// MARK: - MicrophoneLevelMonitor

private final class MicrophoneLevelMonitor {
    private let engine = AVAudioEngine()
    private let thresholdRMS: Float
    private let holdSeconds: TimeInterval
    private let lock = NSLock()
    private var lastActiveAt: Date = .distantPast

    init(thresholdRMS: Float = 0.0015, holdSeconds: TimeInterval = 1.5) throws {
        self.thresholdRMS = thresholdRMS
        self.holdSeconds = holdSeconds
        try configureAndStart()
    }

    deinit {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func isActive(at date: Date) -> Bool {
        lock.lock()
        let last = lastActiveAt
        lock.unlock()
        return date.timeIntervalSince(last) <= holdSeconds
    }

    private func configureAndStart() throws {
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = Self.rootMeanSquare(from: buffer)
            guard rms >= self.thresholdRMS else { return }
            self.lock.lock()
            self.lastActiveAt = Date()
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    private static func rootMeanSquare(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?.pointee else {
            return 0
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return 0
        }

        var sumSquares: Float = 0
        for i in 0 ..< frameCount {
            let s = channel[i]
            sumSquares += s * s
        }
        return sqrt(sumSquares / Float(frameCount))
    }
}
