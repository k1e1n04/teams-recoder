import Foundation
import XCTest
@testable import TeamsAutoRecorder

final class AudioNormalizerTests: XCTestCase {
    func testNormalizeReturns16kMonoFloatSamples() throws {
        let input = try makeTempPCMFile(lines: ["0.1", "0.2", "0.3"])
        let normalizer = AudioNormalizer()

        let normalized = try normalizer.normalize(audioURL: input)
        XCTAssertEqual(normalized.sampleRate, 16_000)
        XCTAssertEqual(normalized.channelCount, 1)
        XCTAssertFalse(normalized.samples.isEmpty)
    }

    func testNormalizeThrowsWhenFileMissing() {
        let url = URL(fileURLWithPath: "/tmp/not-found-\(UUID().uuidString).raw")
        let normalizer = AudioNormalizer()
        XCTAssertThrowsError(try normalizer.normalize(audioURL: url))
    }

    func testNormalizeThrowsWhenFileIsEmpty() throws {
        let input = try makeTempPCMFile(lines: [])
        let normalizer = AudioNormalizer()
        XCTAssertThrowsError(try normalizer.normalize(audioURL: input))
    }
}

private func makeTempPCMFile(lines: [String]) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("audio.raw")
    let body = lines.joined(separator: "\n")
    try body.write(to: file, atomically: true, encoding: .utf8)
    return file
}
