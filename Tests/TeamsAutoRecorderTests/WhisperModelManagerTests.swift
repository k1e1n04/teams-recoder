import Foundation
import XCTest
@testable import TeamsAutoRecorder

final class WhisperModelManagerTests: XCTestCase {
    func testResolveModelDownloadsWhenMissing() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let downloader = ModelDownloaderSpy(result: .success(temp.appendingPathComponent("medium")))
        let manager = WhisperModelManager(baseDirectory: temp, downloader: downloader, fileManager: .default)

        _ = try await manager.resolveModel(named: "medium")
        XCTAssertEqual(downloader.calls, ["medium"])
    }

    func testResolveModelReturnsExistingDirectoryWithoutDownload() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let existing = temp.appendingPathComponent("medium", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let downloader = ModelDownloaderSpy(result: .success(existing))
        let manager = WhisperModelManager(baseDirectory: temp, downloader: downloader, fileManager: .default)

        let resolved = try await manager.resolveModel(named: "medium")
        XCTAssertEqual(resolved.path, existing.path)
        XCTAssertTrue(downloader.calls.isEmpty)
    }

    func testResolveModelThrowsClassifiedErrorWhenDownloadFails() async {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let downloader = ModelDownloaderSpy(result: .failure(StubError.forced))
        let manager = WhisperModelManager(baseDirectory: temp, downloader: downloader, fileManager: .default)

        do {
            _ = try await manager.resolveModel(named: "medium")
            XCTFail("Expected failure")
        } catch let error as WhisperModelManagerError {
            if case .modelDownloadFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class ModelDownloaderSpy: WhisperModelDownloading {
    private(set) var calls: [String] = []
    private let result: Result<URL, Error>

    init(result: Result<URL, Error>) {
        self.result = result
    }

    func downloadModel(named modelName: String, into directory: URL) async throws -> URL {
        calls.append(modelName)
        return try result.get()
    }
}
