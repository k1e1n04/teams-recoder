import Foundation
import WhisperKit

public final class DefaultWhisperModelDownloader: WhisperModelDownloading {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func downloadModel(named modelName: String, into directory: URL) async throws -> URL {
        let resolved = directory.appendingPathComponent(modelName, isDirectory: true)
        let stagingDir = directory.appendingPathComponent(".whisperkit-staging", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingDir) }

        let downloaded = try await WhisperKit.download(variant: modelName, downloadBase: stagingDir)

        if fileManager.fileExists(atPath: resolved.path) {
            try fileManager.removeItem(at: resolved)
        }
        try fileManager.moveItem(at: downloaded, to: resolved)
        return resolved
    }
}
