import Foundation
import XCTest
@testable import TeamsAutoRecorder

final class WhisperKitTranscriberTests: XCTestCase {
    func testTranscribeBuildsTranscriptFromInferenceResult() async throws {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(),
            normalizer: FakeNormalizer(),
            inferencer: FakeWhisperInferencer()
        )

        let result = try await transcriber.transcribe(
            sessionID: "s1",
            audioURL: URL(fileURLWithPath: "/tmp/audio.raw")
        )

        XCTAssertEqual(result.sessionID, "s1")
        XCTAssertEqual(result.fullText, "hello world")
        XCTAssertEqual(result.segments.count, 1)
    }

    func testTranscribeClassifiesModelResolutionError() async {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(error: StubError.forced),
            normalizer: FakeNormalizer(),
            inferencer: FakeWhisperInferencer()
        )

        do {
            _ = try await transcriber.transcribe(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.raw"))
            XCTFail("Expected failure")
        } catch let error as WhisperTranscriberError {
            if case .modelLoadFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeClassifiesNormalizationError() async {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(),
            normalizer: FakeNormalizer(error: StubError.forced),
            inferencer: FakeWhisperInferencer()
        )

        do {
            _ = try await transcriber.transcribe(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.raw"))
            XCTFail("Expected failure")
        } catch let error as WhisperTranscriberError {
            if case .transcriptionFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeClassifiesInferenceError() async {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(),
            normalizer: FakeNormalizer(),
            inferencer: FakeWhisperInferencer(error: StubError.forced)
        )

        do {
            _ = try await transcriber.transcribe(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.raw"))
            XCTFail("Expected failure")
        } catch let error as WhisperTranscriberError {
            if case .transcriptionFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct FakeModelManager: WhisperModelManaging {
    var error: Error?

    func resolveModel(named modelName: String) async throws -> URL {
        if let error {
            throw error
        }
        return URL(fileURLWithPath: "/tmp/\(modelName)")
    }
}

private struct FakeNormalizer: AudioNormalizing {
    var error: Error?

    func normalize(audioURL: URL) throws -> NormalizedAudio {
        if let error {
            throw error
        }
        return NormalizedAudio(sampleRate: 16_000, channelCount: 1, samples: [0.1, 0.2, 0.3])
    }
}

private struct FakeWhisperInferencer: WhisperInferencing {
    var error: Error?

    func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment] {
        if let error {
            throw error
        }
        return [TranscriptSegment(start: 0, end: 1, text: "hello world")]
    }
}
