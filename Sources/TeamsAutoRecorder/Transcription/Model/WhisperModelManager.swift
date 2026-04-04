import Foundation

public enum WhisperModelManagerError: Error {
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
}

public final class WhisperModelManager: WhisperModelManaging {
    private let baseDirectory: URL
    private let downloader: WhisperModelDownloading
    private let fileManager: FileManager

    public init(baseDirectory: URL, downloader: WhisperModelDownloading, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.downloader = downloader
        self.fileManager = fileManager
    }

    public func resolveModel(named modelName: String) async throws -> URL {
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            throw WhisperModelManagerError.modelLoadFailed(String(describing: error))
        }

        let expected = baseDirectory.appendingPathComponent(modelName, isDirectory: true)
        if fileManager.fileExists(atPath: expected.path) {
            return expected
        }

        do {
            return try await downloader.downloadModel(named: modelName, into: baseDirectory)
        } catch {
            throw WhisperModelManagerError.modelDownloadFailed(String(describing: error))
        }
    }
}
