import Foundation

public final class RecorderOrchestrator {
    public let repository: SessionRepository
    public let transcriptionQueue: TranscriptionQueue

    private let detector: MeetingDetector
    private let captureEngine: CaptureEngine
    private var appStateMachine = AppStateMachine()
    private var currentSessionStartedAt: Date?

    public var isRecording: Bool {
        if case .recording = appStateMachine.state { return true }
        return false
    }

    public init(
        detector: MeetingDetector,
        captureEngine: CaptureEngine,
        worker: TranscriptionWorker,
        repository: SessionRepository,
        artifactStore: SessionAudioArtifactStore? = nil
    ) {
        self.detector = detector
        self.captureEngine = captureEngine
        self.repository = repository
        self.transcriptionQueue = TranscriptionQueue(worker: worker, repository: repository, artifactStore: artifactStore)
    }

    @discardableResult
    public func tick(
        windowActive: Bool,
        audioActive: Bool,
        meetingAppRunning: Bool = true,
        now: Date
    ) async -> MeetingDetectorEvent? {
        let event = detector.ingest(windowActive: windowActive, audioActive: audioActive, meetingAppRunning: meetingAppRunning, at: now)
        guard let event else {
            if case .recording = appStateMachine.state {
                try? captureEngine.appendTeams(samples: [audioActive ? 1 : 0], timestamp: now.timeIntervalSince1970)
                try? captureEngine.appendMic(samples: [audioActive ? 1 : 0], timestamp: now.timeIntervalSince1970)
            }
            return nil
        }

        switch event {
        case let .started(sessionID):
            guard appStateMachine.startRecording(sessionID: sessionID, startedAt: now) else {
                return nil
            }
            currentSessionStartedAt = now
            do {
                try captureEngine.start(sessionID: sessionID)
            } catch {
                appStateMachine.reset()
                currentSessionStartedAt = nil
                return .transcriptionFailed(sessionID: sessionID, reason: String(describing: error))
            }
            try? captureEngine.appendTeams(samples: [1], timestamp: now.timeIntervalSince1970)
            try? captureEngine.appendMic(samples: [1], timestamp: now.timeIntervalSince1970)
            return event

        case let .stopped(sessionID):
            await finishSession(sessionID: sessionID, now: now)
            return .stopped(sessionID: sessionID)

        case .fallbackToNotifyOnly:
            return .fallbackToNotifyOnly

        case .transcriptionFailed:
            return nil
        }
    }

    public func startManualRecording(now: Date = Date()) throws {
        let sessionID = "manual-\(Int(now.timeIntervalSince1970))"
        guard appStateMachine.startRecording(sessionID: sessionID, startedAt: now) else { return }
        currentSessionStartedAt = now
        try captureEngine.start(sessionID: sessionID)
    }

    public func stopManualRecording(now: Date = Date()) async -> MeetingDetectorEvent? {
        guard case let .recording(sessionID) = appStateMachine.state else { return nil }
        await finishSession(sessionID: sessionID, now: now)
        return .stopped(sessionID: sessionID)
    }

    private func finishSession(sessionID: String, now: Date) async {
        guard let artifact = try? captureEngine.stop() else {
            appStateMachine.reset()
            currentSessionStartedAt = nil
            return
        }
        let job = TranscriptionQueue.Job(
            sessionID: sessionID,
            audioURL: artifact.mixedAudioURL,
            startedAt: currentSessionStartedAt?.timeIntervalSince1970 ?? now.timeIntervalSince1970,
            endedAt: now.timeIntervalSince1970
        )
        await transcriptionQueue.enqueue(job)
        appStateMachine.reset()
        currentSessionStartedAt = nil
    }
}

extension RecorderOrchestrator: @unchecked Sendable {}

public struct AppBootstrap {
    public init() {}

    public func makeDefaultOrchestrator(storageDirectory: URL) throws -> RecorderOrchestrator {
        let db = try Database(path: storageDirectory.appendingPathComponent("teams-auto-recorder.sqlite").path)
        try db.migrate()
        let artifactStore = SessionAudioArtifactStore(directory: storageDirectory)
        try artifactStore.cleanupExpiredArtifacts()
        let repository = SessionRepository(database: db, fileManager: .default, artifactStore: artifactStore)
        let appSupport = try AppSupportDirectoryResolver().resolve()
        let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)
        let modelManager = WhisperModelManager(baseDirectory: modelsDir, downloader: DefaultWhisperModelDownloader())
        let transcriber = WhisperKitTranscriber(
            modelManager: modelManager,
            inferencer: DefaultWhisperInferencer()
        )
        return RecorderOrchestrator(
            detector: MeetingDetector(
                config: MeetingDetectorConfig(
                    startUISeconds: 4,
                    audioWindowSeconds: 6,
                    audioRequiredRatio: 0.35,
                    stopGraceSeconds: 6,
                    minRecordingSeconds: 30,
                    falsePositiveCapPerDay: 5
                )
            ),
            captureEngine: CaptureEngine(mixer: AudioMixer(), outputDirectory: storageDirectory),
            worker: TranscriptionWorker(transcriber: transcriber, maxRetries: 2),
            repository: repository,
            artifactStore: artifactStore
        )
    }
}

@MainActor
public final class RecorderRuntime {
    private let windowSignalProvider: TeamsWindowSignalProviding
    private let audioSignalProvider: TeamsAudioSignalProviding
    private let meetingAppRunningProvider: (Date) -> Bool
    private let orchestrator: RecorderOrchestrator?
    private let tickHandler: (@MainActor (Bool, Bool, Date) async -> MeetingDetectorEvent?)?

    public init(
        windowSignalProvider: TeamsWindowSignalProviding,
        audioSignalProvider: TeamsAudioSignalProviding,
        tickHandler: @escaping @MainActor (Bool, Bool, Date) async -> MeetingDetectorEvent?
    ) {
        self.windowSignalProvider = windowSignalProvider
        self.audioSignalProvider = audioSignalProvider
        self.meetingAppRunningProvider = { _ in true }
        self.orchestrator = nil
        self.tickHandler = tickHandler
    }

    public init(
        orchestrator: RecorderOrchestrator,
        windowSignalProvider: TeamsWindowSignalProviding,
        audioSignalProvider: TeamsAudioSignalProviding,
        meetingAppRunningProvider: @escaping (Date) -> Bool = { _ in true }
    ) {
        self.windowSignalProvider = windowSignalProvider
        self.audioSignalProvider = audioSignalProvider
        self.meetingAppRunningProvider = meetingAppRunningProvider
        self.orchestrator = orchestrator
        self.tickHandler = nil
    }

    public var isRecording: Bool { orchestrator?.isRecording ?? false }

    public func startManualRecording(now: Date = Date()) throws {
        try orchestrator?.startManualRecording(now: now)
    }

    public func stopManualRecording(now: Date = Date()) async -> MeetingDetectorEvent? {
        await orchestrator?.stopManualRecording(now: now)
    }

    @discardableResult
    public func runIteration(at now: Date = Date()) async -> MeetingDetectorEvent? {
        let windowActive = windowSignalProvider.isMeetingWindowActive(at: now)
        var audioActive = audioSignalProvider.isAudioActive(at: now)
        if windowActive {
            audioActive = true
        }
        let meetingAppRunning = meetingAppRunningProvider(now)
        if let orchestrator {
            return await orchestrator.tick(
                windowActive: windowActive,
                audioActive: audioActive,
                meetingAppRunning: meetingAppRunning,
                now: now
            )
        }
        guard let tickHandler else {
            return nil
        }
        return await tickHandler(windowActive, audioActive, now)
    }
}
