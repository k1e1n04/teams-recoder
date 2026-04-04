import Foundation

public protocol WhisperModelManaging {
    func resolveModel(named modelName: String) async throws -> URL
}

public protocol WhisperModelDownloading {
    func downloadModel(named modelName: String, into directory: URL) async throws -> URL
}
