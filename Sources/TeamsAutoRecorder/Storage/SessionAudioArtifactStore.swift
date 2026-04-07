import Foundation

public final class SessionAudioArtifactStore {
    private let directory: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let failedRetentionInterval: TimeInterval

    public init(
        directory: URL,
        fileManager: FileManager = .default,
        failedRetentionDays: Int = 7,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.failedRetentionInterval = TimeInterval(failedRetentionDays * 24 * 60 * 60)
    }

    public func audioURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("\(sessionID)-mixed.wav")
    }

    public func deleteArtifact(for sessionID: String) throws {
        let url = audioURL(for: sessionID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func cleanupExpiredArtifacts() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let cutoff = nowProvider().addingTimeInterval(-failedRetentionInterval)
        for url in fileURLs where url.pathExtension == "wav" && url.lastPathComponent.hasSuffix("-mixed.wav") {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if modifiedAt < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
