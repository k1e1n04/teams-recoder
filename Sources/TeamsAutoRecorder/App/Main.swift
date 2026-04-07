import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices

@main
struct TeamsAutoRecorderApp: App {
    @StateObject private var viewModel = DashboardFactory.makeViewModel()
    private let notificationSink = MacOSNotificationSink()
    @StateObject private var runtimeController = RuntimeController()

    var body: some Scene {
        WindowGroup("TeamsAutoRecorder") {
            DashboardView(viewModel: viewModel, runtimeController: runtimeController)
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
                    runtimeController.startIfNeeded(notificationSink: notificationSink) {
                        viewModel.loadSessions()
                    }
                }
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var runtimeController: RuntimeController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Teams Auto Recorder")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.1, green: 0.13, blue: 0.24))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("検知状態")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runtimeController.statusText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(runtimeController.statusText == "録音中" ? .red : .primary)
                }

                Button(action: { runtimeController.toggleManualRecording() }) {
                    Label(
                        runtimeController.isManuallyRecording ? "録音停止" : "手動録音",
                        systemImage: runtimeController.isManuallyRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(runtimeController.isManuallyRecording ? .red : .accentColor)

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
            let base = try AppSupportDirectoryResolver().resolve()
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

@MainActor
private final class RuntimeController: ObservableObject {
    @Published private(set) var statusText: String = "待機中"
    @Published private(set) var isManuallyRecording: Bool = false
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
            let windowProvider = TeamsWindowSignalProvider(holdSeconds: 8, evaluator: { _ in
                self.hasVisibleTeamsWindow()
            })
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
                        if let event = await self.runtime?.runIteration() {
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

    private func consume(_ event: MeetingDetectorEvent) {
        switch event {
        case let .started(sessionID):
            statusText = "録音中"
            notificationSink?.sendSilent(message: "Teams 会議を検知して録音を開始しました (\(sessionID))")
        case .stopped:
            statusText = "待機中"
            onSessionSaved?()
        case .fallbackToNotifyOnly:
            statusText = "通知のみ"
        }
    }

    func toggleManualRecording() {
        if isManuallyRecording {
            isManuallyRecording = false
            statusText = "文字起こし中..."
            Task { @MainActor in
                await self.runtime?.stopManualRecording()
                self.statusText = "待機中"
                self.onSessionSaved?()
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
