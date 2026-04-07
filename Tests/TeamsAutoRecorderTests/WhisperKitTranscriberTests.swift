import Foundation
import XCTest
@testable import TeamsAutoRecorder

final class WhisperKitTranscriberTests: XCTestCase {
    func testTranscribeBuildsTranscriptFromInferenceResult() async throws {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(),
            inferencer: FakeWhisperInferencer()
        )

        let result = try await transcriber.transcribe(
            sessionID: "s1",
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav")
        )

        XCTAssertEqual(result.sessionID, "s1")
        XCTAssertEqual(result.fullText, "hello world")
        XCTAssertEqual(result.segments.count, 1)
    }

    func testTranscribeClassifiesModelResolutionError() async {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(error: StubError.forced),
            inferencer: FakeWhisperInferencer()
        )

        do {
            _ = try await transcriber.transcribe(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.wav"))
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

    func testTranscribeClassifiesInferenceError() async {
        let transcriber = WhisperKitTranscriber(
            modelName: "medium",
            modelManager: FakeModelManager(),
            inferencer: FakeWhisperInferencer(error: StubError.forced)
        )

        do {
            _ = try await transcriber.transcribe(sessionID: "s1", audioURL: URL(fileURLWithPath: "/tmp/audio.wav"))
            XCTFail("Expected failure")
        } catch let error as WhisperTranscriberError {
            if case .inferenceFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultInferencerSanitizeKeepsParenthesesAndBrackets() {
        let input = "<|startoftranscript|>(hello) [note] こんにちは<|endoftext|>"
        let cleaned = DefaultWhisperInferencer.sanitizeSegmentText(input)
        XCTAssertEqual(cleaned, "(hello) [note] こんにちは")
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

private struct FakeWhisperInferencer: WhisperInferencing {
    var error: Error?

    func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment] {
        if let error {
            throw error
        }
        return [TranscriptSegment(start: 0, end: 1, text: "hello world")]
    }
}
