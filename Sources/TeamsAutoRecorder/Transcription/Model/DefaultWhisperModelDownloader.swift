import Foundation
import ZIPFoundation

public final class DefaultWhisperModelDownloader: WhisperModelDownloading {
    private let modelRegistryBaseURL: URL
    private let session: URLSession
    private let fileManager: FileManager

    public init(
        modelRegistryBaseURL: URL = URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main")!,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.modelRegistryBaseURL = modelRegistryBaseURL
        self.session = session
        self.fileManager = fileManager
    }

    public func downloadModel(named modelName: String, into directory: URL) async throws -> URL {
        let resolved = directory.appendingPathComponent(modelName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let zipURL = directory.appendingPathComponent("\(modelName).zip")
        let remote = modelRegistryBaseURL.appendingPathComponent("\(modelName).zip")
        let (tempFile, response) = try await session.download(from: remote)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }
        try fileManager.moveItem(at: tempFile, to: zipURL)

        if fileManager.fileExists(atPath: resolved.path) {
            try fileManager.removeItem(at: resolved)
        }
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: zipURL, to: resolved)
        return resolved
    }
}
