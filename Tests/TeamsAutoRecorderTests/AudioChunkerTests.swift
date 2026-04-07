import AVFoundation
import XCTest
@testable import TeamsAutoRecorder

final class AudioChunkerTests: XCTestCase {
    private let sampleRate: Double = 16_000
    private let chunkDuration: Double = 5 * 60   // 300s
    private let overlapDuration: Double = 30      // 30s

    private var chunker: AudioChunker {
        AudioChunker(
            sampleRate: sampleRate,
            chunkDurationSeconds: chunkDuration,
            overlapSeconds: overlapDuration
        )
    }

    // MARK: - chunks(from:)

    func testChunks_shortAudio_returnsOneChunk() throws {
        let url = try makeWAV(durationSeconds: 3 * 60)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].isFirstChunk)
        XCTAssertEqual(chunks[0].chunkOffsetSeconds, 0)
        // WAV ファイルのフレームアライメントにより±1024 サンプルの誤差を許容
        XCTAssertEqual(Double(chunks[0].samples.count) / sampleRate, 3 * 60, accuracy: 0.1)
    }

    func testChunks_exactlyFiveMinutes_returnsOneChunk() throws {
        let url = try makeWAV(durationSeconds: 5 * 60)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(Double(chunks[0].samples.count) / sampleRate, 5 * 60, accuracy: 0.1)
    }

    func testChunks_fiveMinutesThirtySeconds_returnsTwoChunks() throws {
        // 5:30 = chunk 0 reads exactly 5min, chunk 1 reads from 4:30 (270s) for 60s
        let url = try makeWAV(durationSeconds: 5 * 60 + 30)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].isFirstChunk)
        XCTAssertFalse(chunks[1].isFirstChunk)
        XCTAssertEqual(chunks[0].chunkOffsetSeconds, 0)
        XCTAssertEqual(Double(chunks[0].samples.count) / sampleRate, 5 * 60, accuracy: 0.1)
        XCTAssertEqual(chunks[1].chunkOffsetSeconds, 270, accuracy: 0.001)
        XCTAssertEqual(Double(chunks[1].samples.count) / sampleRate, 60, accuracy: 0.1)
    }

    func testChunks_elevenMinutes_returnsThreeChunks() throws {
        // chunk 0: 0..5min, chunk 1: 4:30..9:30 (offset=270s), chunk 2: 9:30..11min (offset=570s)
        let url = try makeWAV(durationSeconds: 11 * 60)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].chunkOffsetSeconds, 0)
        XCTAssertEqual(chunks[1].chunkOffsetSeconds, 270, accuracy: 0.001)
        XCTAssertEqual(chunks[2].chunkOffsetSeconds, 570, accuracy: 0.001)
    }

    func testChunks_emptyAudio_returnsEmpty() throws {
        let url = try makeWAV(durationSeconds: 0)
        let chunks = try chunker.chunks(from: url)
        XCTAssertTrue(chunks.isEmpty)
    }

    // MARK: - mergeSegments

    func testMerge_singleChunk_keepsAllSegments() {
        let info = AudioChunkInfo(samples: [], chunkOffsetSeconds: 0, isFirstChunk: true)
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "hello"),
            TranscriptSegment(start: 5, end: 10, text: "world")
        ]

        let merged = AudioChunker.mergeSegments(
            chunks: [(info, segments)],
            overlapSeconds: overlapDuration
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, 0)
        XCTAssertEqual(merged[1].start, 5)
    }

    func testMerge_secondChunk_discardsOverlapSegments() {
        // Chunk 0: covers 0..300s
        let info0 = AudioChunkInfo(samples: [], chunkOffsetSeconds: 0, isFirstChunk: true)
        let segs0 = [TranscriptSegment(start: 285, end: 295, text: "end of chunk 0")]

        // Chunk 1: file position 270s, WhisperKit sees 0..60s
        //   - segment at startTime=15 (file 285s) → overlap, discard
        //   - segment at startTime=35 (file 305s) → keep, offset to 305s
        let info1 = AudioChunkInfo(samples: [], chunkOffsetSeconds: 270, isFirstChunk: false)
        let segs1 = [
            TranscriptSegment(start: 15, end: 25, text: "in overlap — discard"),
            TranscriptSegment(start: 35, end: 45, text: "new content")
        ]

        let merged = AudioChunker.mergeSegments(
            chunks: [(info0, segs0), (info1, segs1)],
            overlapSeconds: overlapDuration
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].text, "end of chunk 0")
        XCTAssertEqual(merged[1].text, "new content")
        XCTAssertEqual(merged[1].start, 305, accuracy: 0.001)  // 35 + 270
        XCTAssertEqual(merged[1].end, 315, accuracy: 0.001)    // 45 + 270
    }

    func testMerge_timestampOffset_appliedToAllFields() {
        let info = AudioChunkInfo(samples: [], chunkOffsetSeconds: 270, isFirstChunk: false)
        let segments = [TranscriptSegment(start: 30, end: 35, text: "boundary")]

        let merged = AudioChunker.mergeSegments(
            chunks: [(info, segments)],
            overlapSeconds: overlapDuration
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].start, 300, accuracy: 0.001)  // 30 + 270
        XCTAssertEqual(merged[0].end, 305, accuracy: 0.001)    // 35 + 270
        XCTAssertEqual(merged[0].text, "boundary")
    }

    // MARK: - Helpers

    private func makeWAV(durationSeconds: Double) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let sampleCount = Int(durationSeconds * sampleRate)
        guard sampleCount > 0 else { return url }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let channel = buffer.floatChannelData!.pointee
        for i in 0..<sampleCount {
            channel[i] = Float(i % 1000) / 1000.0  // simple ramp, avoids all-zeros
        }
        try file.write(from: buffer)
        return url
    }
}
