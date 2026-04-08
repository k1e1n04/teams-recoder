import Foundation

public actor TranscriptionQueue {
    public struct Job {
        public let sessionID: String
        public let audioURL: URL
        public let startedAt: TimeInterval
        public let endedAt: TimeInterval

        public init(sessionID: String, audioURL: URL, startedAt: TimeInterval, endedAt: TimeInterval) {
            self.sessionID = sessionID
            self.audioURL = audioURL
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    nonisolated(unsafe) private let worker: TranscriptionWorker
    private let repository: SessionRepository
    private let artifactStore: SessionAudioArtifactStore?
    private var jobs: [Job] = []
    private var isProcessing = false
    private var onQueueChanged: (@MainActor (Int) -> Void)?
    private var onJobCompleted: (@MainActor (String, Bool) -> Void)?

    public init(
        worker: TranscriptionWorker,
        repository: SessionRepository,
        artifactStore: SessionAudioArtifactStore?
    ) {
        self.worker = worker
        self.repository = repository
        self.artifactStore = artifactStore
    }

    public var pendingCount: Int { jobs.count }

    public func setOnQueueChanged(_ handler: @escaping @MainActor (Int) -> Void) {
        onQueueChanged = handler
    }

    public func setOnJobCompleted(_ handler: @escaping @MainActor (String, Bool) -> Void) {
        onJobCompleted = handler
    }

    public func enqueue(_ job: Job) async {
        jobs.append(job)
        let count = jobs.count
        let cb = onQueueChanged
        await MainActor.run { cb?(count) }
        if !isProcessing {
            Task { await self.processNext() }
        }
    }

    private func processNext() async {
        isProcessing = true
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            let count = jobs.count
            let cb = onQueueChanged
            await MainActor.run { cb?(count) }
            await process(job)
        }
        isProcessing = false
        let cb = onQueueChanged
        await MainActor.run { cb?(0) }
    }

    private func process(_ job: Job) async {
        let result = await worker.run(job: TranscriptionJob(sessionID: job.sessionID, audioURL: job.audioURL))
        let record: SessionRecord
        let success: Bool
        switch result {
        case let .success(transcript):
            record = SessionRecord(
                sessionID: job.sessionID,
                startedAt: job.startedAt,
                endedAt: job.endedAt,
                transcriptText: transcript.fullText
            )
            success = true
            try? artifactStore?.deleteArtifact(for: job.sessionID)
        case let .failure(failure):
            record = SessionRecord(
                sessionID: job.sessionID,
                startedAt: job.startedAt,
                endedAt: job.endedAt,
                transcriptText: "[transcription failed] \(failure.description)",
                failureStage: failure.stage,
                failureReason: failure.description
            )
            success = false
        }
        try? repository.saveSession(record)
        let sessionID = job.sessionID
        let completedCb = onJobCompleted
        await MainActor.run { completedCb?(sessionID, success) }
    }
}
