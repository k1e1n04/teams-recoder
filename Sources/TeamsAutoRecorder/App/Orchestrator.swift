import Foundation

public final class RecorderOrchestrator {
    private enum SessionFinishOutcome {
        case success
        case failure(TranscriptionFailure)
    }

    public let repository: SessionRepository

    private let detector: MeetingDetector
    private let captureEngine: CaptureEngine
    private let worker: TranscriptionWorker
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
        repository: SessionRepository
    ) {
        self.detector = detector
        self.captureEngine = captureEngine
        self.worker = worker
        self.repository = repository
    }

    @discardableResult
    public func tick(
        windowActive: Bool,
        audioActive: Bool,
        now: Date,
        onTranscriptionStarted: (@MainActor @Sendable () -> Void)? = nil
    ) async -> MeetingDetectorEvent? {
        let event = detector.ingest(windowActive: windowActive, audioActive: audioActive, at: now)
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
            if let onTranscriptionStarted {
                await MainActor.run(body: onTranscriptionStarted)
            }
            let outcome = await finishSession(sessionID: sessionID, now: now)
            switch outcome {
            case .success:
                return .stopped(sessionID: sessionID)
            case let .failure(failure):
                return .transcriptionFailed(sessionID: sessionID, reason: failure.description)
            }

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
        let outcome = await finishSession(sessionID: sessionID, now: now)
        switch outcome {
        case .success:
            return .stopped(sessionID: sessionID)
        case let .failure(failure):
            return .transcriptionFailed(sessionID: sessionID, reason: failure.description)
        }
    }

    private func finishSession(sessionID: String, now: Date) async -> SessionFinishOutcome {
        _ = appStateMachine.startTranscription()
        guard let artifact = try? captureEngine.stop() else {
            appStateMachine.reset()
            return .failure(.init(
                attempts: 0,
                stage: .captureFinalize,
                description: "failed to finalize captured audio"
            ))
        }

        let result = await worker.run(job: .init(sessionID: sessionID, audioURL: artifact.mixedAudioURL))
        switch result {
        case let .success(transcript):
            let startedAt = currentSessionStartedAt?.timeIntervalSince1970 ?? now.timeIntervalSince1970
            let record = SessionRecord(
                sessionID: sessionID,
                startedAt: startedAt,
                endedAt: now.timeIntervalSince1970,
                transcriptText: transcript.fullText
            )
            do {
                try repository.saveSession(record)
            } catch {
                appStateMachine.reset()
                return .failure(.init(
                    attempts: 0,
                    stage: .sessionSave,
                    description: "sessionSaveFailed(\(String(describing: error)))"
                ))
            }
            _ = appStateMachine.finish(transcriptPath: artifact.mixedAudioURL.path)
            appStateMachine.reset()
            return .success
        case let .failure(failure):
            let startedAt = currentSessionStartedAt?.timeIntervalSince1970 ?? now.timeIntervalSince1970
            let record = SessionRecord(
                sessionID: sessionID,
                startedAt: startedAt,
                endedAt: now.timeIntervalSince1970,
                transcriptText: "[transcription failed] \(failure.description)",
                failureStage: failure.stage,
                failureReason: failure.description
            )
            do {
                try repository.saveSession(record)
            } catch {
                appStateMachine.reset()
                return .failure(.init(
                    attempts: 0,
                    stage: .sessionSave,
                    description: "sessionSaveFailed(\(String(describing: error)))"
                ))
            }
            _ = appStateMachine.finish(transcriptPath: artifact.mixedAudioURL.path)
            appStateMachine.reset()
            return .failure(failure)
        }
    }
}

extension RecorderOrchestrator: @unchecked Sendable {}

public struct AppBootstrap {
    public init() {}

    public func makeDefaultOrchestrator(storageDirectory: URL) throws -> RecorderOrchestrator {
        let db = try Database(path: storageDirectory.appendingPathComponent("teams-auto-recorder.sqlite").path)
        try db.migrate()
        let repository = SessionRepository(database: db, fileManager: .default)
        let appSupport = try AppSupportDirectoryResolver().resolve()
        let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)
        let modelManager = WhisperModelManager(baseDirectory: modelsDir, downloader: DefaultWhisperModelDownloader())
        let transcriber = WhisperKitTranscriber(
            modelManager: modelManager,
            normalizer: AudioNormalizer(),
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
            repository: repository
        )
    }
}

@MainActor
public final class RecorderRuntime {
    private let windowSignalProvider: TeamsWindowSignalProviding
    private let audioSignalProvider: TeamsAudioSignalProviding
    private let orchestrator: RecorderOrchestrator?
    private let tickHandler: (@MainActor (Bool, Bool, Date) async -> MeetingDetectorEvent?)?

    public init(
        windowSignalProvider: TeamsWindowSignalProviding,
        audioSignalProvider: TeamsAudioSignalProviding,
        tickHandler: @escaping @MainActor (Bool, Bool, Date) async -> MeetingDetectorEvent?
    ) {
        self.windowSignalProvider = windowSignalProvider
        self.audioSignalProvider = audioSignalProvider
        self.orchestrator = nil
        self.tickHandler = tickHandler
    }

    public init(
        orchestrator: RecorderOrchestrator,
        windowSignalProvider: TeamsWindowSignalProviding,
        audioSignalProvider: TeamsAudioSignalProviding
    ) {
        self.windowSignalProvider = windowSignalProvider
        self.audioSignalProvider = audioSignalProvider
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
    public func runIteration(
        at now: Date = Date(),
        onTranscriptionStarted: (@MainActor @Sendable () -> Void)? = nil
    ) async -> MeetingDetectorEvent? {
        let windowActive = windowSignalProvider.isMeetingWindowActive(at: now)
        var audioActive = audioSignalProvider.isAudioActive(at: now)
        if windowActive {
            audioActive = true
        }
        if let orchestrator {
            return await orchestrator.tick(
                windowActive: windowActive,
                audioActive: audioActive,
                now: now,
                onTranscriptionStarted: onTranscriptionStarted
            )
        }
        guard let tickHandler else {
            return nil
        }
        return await tickHandler(windowActive, audioActive, now)
    }
}
