import Foundation

public final class RecorderOrchestrator {
    public let repository: SessionRepository

    private let detector: MeetingDetector
    private let captureEngine: CaptureEngine
    private let worker: TranscriptionWorker
    private var appStateMachine = AppStateMachine()
    private var currentSessionStartedAt: Date?

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
    public func tick(windowActive: Bool, audioActive: Bool, now: Date) async -> MeetingDetectorEvent? {
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
            currentSessionStartedAt = now
            _ = appStateMachine.startRecording(sessionID: sessionID, startedAt: now)
            try? captureEngine.start(sessionID: sessionID)
            try? captureEngine.appendTeams(samples: [1], timestamp: now.timeIntervalSince1970)
            try? captureEngine.appendMic(samples: [1], timestamp: now.timeIntervalSince1970)
            return event

        case let .stopped(sessionID):
            _ = appStateMachine.startTranscription()
            guard let artifact = try? captureEngine.stop() else {
                appStateMachine.reset()
                return event
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
                try? repository.saveSession(record)
                _ = appStateMachine.finish(transcriptPath: artifact.mixedAudioURL.path)
            case .failure:
                appStateMachine.reset()
            }

            return .stopped(sessionID: sessionID)

        case .fallbackToNotifyOnly:
            return .fallbackToNotifyOnly
        }
    }
}

public struct AppBootstrap {
    public init() {}

    public func makeDefaultOrchestrator(storageDirectory: URL) throws -> RecorderOrchestrator {
        let db = try Database(path: storageDirectory.appendingPathComponent("teams-auto-recorder.sqlite").path)
        try db.migrate()
        let repository = SessionRepository(database: db, fileManager: .default)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TeamsAutoRecorder")
        let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)
        let modelManager = WhisperModelManager(baseDirectory: modelsDir, downloader: DefaultWhisperModelDownloader())
        let transcriber = WhisperKitTranscriber(
            modelManager: modelManager,
            normalizer: AudioNormalizer(),
            inferencer: DefaultWhisperInferencer()
        )
        return RecorderOrchestrator(
            detector: MeetingDetector(),
            captureEngine: CaptureEngine(mixer: AudioMixer(), outputDirectory: storageDirectory),
            worker: TranscriptionWorker(transcriber: transcriber, maxRetries: 2),
            repository: repository
        )
    }
}
