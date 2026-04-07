# Long Audio Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 音声保存をテキストRAWからWAVに変更し、WhisperKit推論を5分チャンクで実行することで1時間以上の会議録音に対応する。

**Architecture:** `CaptureEngine.stop()` が `AVAudioFile`（WAV, Float32, 16kHz, mono）で混合音声を書き出す。`AudioChunker` が WAV を5分チャンク（30秒オーバーラップ）に分割し、`DefaultWhisperInferencer` がチャンクごとに WhisperKit を呼び出してセグメントをタイムスタンプオフセット補正後にマージする。`AudioNormalizer` / `AudioNormalizing` は廃止。外部インターフェース（`AudioTranscribing`, `TranscriptOutput`）は変更なし。

**Tech Stack:** `AVFoundation.AVAudioFile`（WAV読み書き）, `WhisperKit`（既存）, `XCTest`

---

## ファイル構造

**削除:**
- `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizer.swift`
- `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizing.swift`
- `Tests/TeamsAutoRecorderTests/AudioNormalizerTests.swift`

**新規作成:**
- `Sources/TeamsAutoRecorder/Transcription/Audio/AudioChunker.swift`
- `Tests/TeamsAutoRecorderTests/AudioChunkerTests.swift`

**変更:**
- `Sources/TeamsAutoRecorder/Capture/CaptureEngine.swift`
- `Sources/TeamsAutoRecorder/Storage/SessionAudioArtifactStore.swift`
- `Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift`
- `Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`
- `Sources/TeamsAutoRecorder/App/Orchestrator.swift`
- `Tests/TeamsAutoRecorderTests/CaptureEngineTests.swift`
- `Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift`
- `Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift`

---

### Task 1: CaptureEngine が WAV で音声を書き出す + SessionAudioArtifactStore を .wav 対応にする

**Files:**
- Modify: `Sources/TeamsAutoRecorder/Capture/CaptureEngine.swift:116-148`
- Modify: `Sources/TeamsAutoRecorder/Storage/SessionAudioArtifactStore.swift:21-45`
- Modify: `Tests/TeamsAutoRecorderTests/CaptureEngineTests.swift`

- [ ] **Step 1: 失敗するテストを追加する**

`Tests/TeamsAutoRecorderTests/CaptureEngineTests.swift` のファイル先頭に `import AVFoundation` を追加し、`CaptureEngineTests` クラス内に以下を追加する:

```swift
func testStopWritesMixedAudioAsWAV() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let engine = CaptureEngine(
        mixer: AudioMixer(),
        outputDirectory: dir,
        liveCaptureFactory: { _ in nil }
    )
    try engine.start(sessionID: "wav-test")
    try engine.appendTeams(samples: [0.5], timestamp: 0)
    try engine.appendMic(samples: [0.5], timestamp: 0)
    let artifact = try engine.stop()

    XCTAssertEqual(artifact.mixedAudioURL.pathExtension, "wav")
    let audioFile = try AVAudioFile(forReading: artifact.mixedAudioURL)
    XCTAssertEqual(audioFile.processingFormat.sampleRate, 16_000, accuracy: 0.1)
    XCTAssertEqual(audioFile.processingFormat.channelCount, 1)
}
```

- [ ] **Step 2: テストを実行して失敗を確認**

```bash
swift test --filter CaptureEngineTests/testStopWritesMixedAudioAsWAV
```

Expected: FAIL — `pathExtension` が "raw" で "wav" ではない。

- [ ] **Step 3: CaptureEngine.stop() を WAV 書き込みに変更する**

`Sources/TeamsAutoRecorder/Capture/CaptureEngine.swift` の `stop()` 内の以下を変更する:

```swift
// 変更前（stop() 内）
let mixedURL = outputDirectory.appendingPathComponent("\(sessionID)-mixed.raw")
// ...（mixedSamples 決定後）
let body = mixedSamples.map { String(format: "%.6f", $0) }.joined(separator: "\n")
try body.data(using: .utf8)?.write(to: mixedURL)

// 変更後
let mixedURL = outputDirectory.appendingPathComponent("\(sessionID)-mixed.wav")
// ...（mixedSamples 決定後）
try Self.writeWAV(samples: mixedSamples, to: mixedURL)
```

同ファイルの `isEffectivelySilent` の直前に以下のプライベートメソッドを追加する:

```swift
private static func writeWAV(samples: [Float], to url: URL) throws {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
    guard !samples.isEmpty else { return }
    let frameCount = AVAudioFrameCount(samples.count)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    samples.withUnsafeBufferPointer { ptr in
        buffer.floatChannelData!.pointee.initialize(from: ptr.baseAddress!, count: samples.count)
    }
    try audioFile.write(from: buffer)
}
```

- [ ] **Step 4: SessionAudioArtifactStore を .wav 対応に変更する**

`Sources/TeamsAutoRecorder/Storage/SessionAudioArtifactStore.swift` を変更する。

`audioURL(for:)`:
```swift
// 変更前
directory.appendingPathComponent("\(sessionID)-mixed.raw")
// 変更後
directory.appendingPathComponent("\(sessionID)-mixed.wav")
```

`cleanupExpiredArtifacts()` のフィルター条件:
```swift
// 変更前
for url in fileURLs where url.pathExtension == "raw" && url.lastPathComponent.hasSuffix("-mixed.raw") {
// 変更後
for url in fileURLs where url.pathExtension == "wav" && url.lastPathComponent.hasSuffix("-mixed.wav") {
```

- [ ] **Step 5: 既存の CaptureEngineTests を WAV 対応に更新する**

`Tests/TeamsAutoRecorderTests/CaptureEngineTests.swift` の末尾（`LiveCaptureSessionStub` の後）に WAV 読み込みヘルパーを追加する:

```swift
private func readWAVSamples(from url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let frameCount = AVAudioFrameCount(file.length)
    guard frameCount > 0 else { return [] }
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(
        start: buffer.floatChannelData!.pointee,
        count: Int(buffer.frameLength)
    ))
}
```

`testStopPrefersLiveCaptureArtifactWhenAvailable` を次のように置き換える（UTF-8テキスト読み込みを WAV 読み込みに変更）:

```swift
func testStopPrefersLiveCaptureArtifactWhenAvailable() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let liveOutput = CapturedAudioSamples(teams: [0.5, 0.5], mic: [0.5, 0.5], mixed: [0.9, 0.1])
    let session = LiveCaptureSessionStub(stopResult: .success(liveOutput))
    let engine = CaptureEngine(
        mixer: AudioMixer(),
        outputDirectory: dir,
        liveCaptureFactory: { _ in session }
    )

    try engine.start(sessionID: "live-1")
    let artifact = try engine.stop()
    let samples = try readWAVSamples(from: artifact.mixedAudioURL)

    XCTAssertEqual(session.startCallCount, 1)
    XCTAssertEqual(session.stopCallCount, 1)
    XCTAssertEqual(samples.count, 2)
    XCTAssertEqual(samples[0], 0.9, accuracy: 0.001)
    XCTAssertEqual(samples[1], 0.1, accuracy: 0.001)
}
```

`testStopFallsBackToMixingLiveInputsWhenRecordedMixIsAllZero` を次のように置き換える:

```swift
func testStopFallsBackToMixingLiveInputsWhenRecordedMixIsAllZero() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let liveOutput = CapturedAudioSamples(
        teams: [0.6, 0.2],
        mic: [0.2, 0.6],
        mixed: [0, 0]
    )
    let session = LiveCaptureSessionStub(stopResult: .success(liveOutput))
    let engine = CaptureEngine(
        mixer: AudioMixer(),
        outputDirectory: dir,
        liveCaptureFactory: { _ in session }
    )

    try engine.start(sessionID: "live-zero-mix")
    let artifact = try engine.stop()
    let samples = try readWAVSamples(from: artifact.mixedAudioURL)

    XCTAssertEqual(samples.count, 2)
    XCTAssertEqual(samples[0], 0.4, accuracy: 0.001)
    XCTAssertEqual(samples[1], 0.4, accuracy: 0.001)
}
```

- [ ] **Step 6: テストを実行してすべて通ることを確認**

```bash
swift test --filter CaptureEngineTests
```

Expected: PASS (5 tests)

- [ ] **Step 7: コミット**

```bash
git add Sources/TeamsAutoRecorder/Capture/CaptureEngine.swift \
        Sources/TeamsAutoRecorder/Storage/SessionAudioArtifactStore.swift \
        Tests/TeamsAutoRecorderTests/CaptureEngineTests.swift
git commit -m "feat(capture): write mixed audio as WAV instead of text RAW"
```

---

### Task 2: AudioChunker — WAV を5分チャンクに分割し、セグメントをマージする

**Files:**
- Create: `Sources/TeamsAutoRecorder/Transcription/Audio/AudioChunker.swift`
- Create: `Tests/TeamsAutoRecorderTests/AudioChunkerTests.swift`

- [ ] **Step 1: 失敗するテストファイルを作成する**

`Tests/TeamsAutoRecorderTests/AudioChunkerTests.swift` を新規作成する:

```swift
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
        XCTAssertEqual(chunks[0].samples.count, Int(3 * 60 * sampleRate))
    }

    func testChunks_exactlyFiveMinutes_returnsOneChunk() throws {
        let url = try makeWAV(durationSeconds: 5 * 60)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].samples.count, Int(5 * 60 * sampleRate))
    }

    func testChunks_fiveMinutesThirtySeconds_returnsTwoChunks() throws {
        // 5:30 = chunk 0 reads exactly 5min, chunk 1 reads from 4:30 (270s) for 60s
        let url = try makeWAV(durationSeconds: 5 * 60 + 30)
        let chunks = try chunker.chunks(from: url)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].isFirstChunk)
        XCTAssertFalse(chunks[1].isFirstChunk)
        XCTAssertEqual(chunks[0].chunkOffsetSeconds, 0)
        XCTAssertEqual(chunks[0].samples.count, Int(5 * 60 * sampleRate))
        XCTAssertEqual(chunks[1].chunkOffsetSeconds, 270, accuracy: 0.001)
        XCTAssertEqual(chunks[1].samples.count, Int(60 * sampleRate))
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
```

- [ ] **Step 2: テストを実行してコンパイルエラーを確認**

```bash
swift test --filter AudioChunkerTests 2>&1 | head -20
```

Expected: compile error — `AudioChunker`, `AudioChunkInfo` が未定義。

- [ ] **Step 3: AudioChunker.swift を実装する**

`Sources/TeamsAutoRecorder/Transcription/Audio/AudioChunker.swift` を新規作成する:

```swift
import AVFoundation
import Foundation

public struct AudioChunkInfo {
    public let samples: [Float]
    public let chunkOffsetSeconds: Double
    public let isFirstChunk: Bool

    public init(samples: [Float], chunkOffsetSeconds: Double, isFirstChunk: Bool) {
        self.samples = samples
        self.chunkOffsetSeconds = chunkOffsetSeconds
        self.isFirstChunk = isFirstChunk
    }
}

public struct AudioChunker {
    public let sampleRate: Double
    public let chunkDurationSeconds: Double
    public let overlapSeconds: Double

    public var chunkSampleCount: Int { Int(chunkDurationSeconds * sampleRate) }
    public var overlapSampleCount: Int { Int(overlapSeconds * sampleRate) }

    public init(
        sampleRate: Double = 16_000,
        chunkDurationSeconds: Double = 5 * 60,
        overlapSeconds: Double = 30
    ) {
        self.sampleRate = sampleRate
        self.chunkDurationSeconds = chunkDurationSeconds
        self.overlapSeconds = overlapSeconds
    }

    /// WAV ファイルを読み込み、チャンクの配列を返す。
    ///
    /// - チャンク 0 はファイル先頭から chunkDurationSeconds 分を読む（オーバーラップなし）。
    /// - チャンク i > 0 はチャンク i-1 の末尾 overlapSeconds 分から読み始め、
    ///   chunkDurationSeconds + overlapSeconds 分（またはファイル末尾まで）を読む。
    /// - `chunkOffsetSeconds` は読み始めのファイル内絶対時刻（秒）。
    public func chunks(from audioURL: URL) throws -> [AudioChunkInfo] {
        let file = try AVAudioFile(forReading: audioURL)
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        let format = file.processingFormat
        var result: [AudioChunkInfo] = []
        var chunkIndex = 0

        while true {
            // 新しい内容の先頭フレーム（前チャンクが担当した範囲の終端）
            let newContentStartFrame = chunkIndex * chunkSampleCount
            if newContentStartFrame >= totalFrames { break }

            let isFirstChunk = chunkIndex == 0
            let readFromFrame: Int
            let readCount: Int

            if isFirstChunk {
                // チャンク 0: オーバーラップなしで先頭から読む
                readFromFrame = 0
                readCount = min(chunkSampleCount, totalFrames)
            } else {
                // チャンク i: overlapSeconds 分だけ前から読み始める
                readFromFrame = max(0, newContentStartFrame - overlapSampleCount)
                readCount = min(chunkSampleCount + overlapSampleCount, totalFrames - readFromFrame)
            }

            let chunkOffsetSeconds = Double(readFromFrame) / sampleRate

            file.framePosition = AVAudioFramePosition(readFromFrame)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(readCount))!
            try file.read(into: buffer, frameCount: AVAudioFrameCount(readCount))

            let samples = Array(UnsafeBufferPointer(
                start: buffer.floatChannelData!.pointee,
                count: Int(buffer.frameLength)
            ))

            result.append(AudioChunkInfo(
                samples: samples,
                chunkOffsetSeconds: chunkOffsetSeconds,
                isFirstChunk: isFirstChunk
            ))

            chunkIndex += 1
        }

        return result
    }

    /// 各チャンクの推論結果セグメントをマージして単一タイムラインに変換する。
    ///
    /// - 非先頭チャンクのオーバーラップ領域（startTime < overlapSeconds）のセグメントを破棄する。
    /// - 残ったセグメントに chunkOffsetSeconds を加算して絶対時刻に変換する。
    public static func mergeSegments(
        chunks: [(info: AudioChunkInfo, segments: [TranscriptSegment])],
        overlapSeconds: Double
    ) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for (info, segments) in chunks {
            for segment in segments {
                if !info.isFirstChunk && segment.start < overlapSeconds {
                    continue
                }
                result.append(TranscriptSegment(
                    start: segment.start + info.chunkOffsetSeconds,
                    end: segment.end + info.chunkOffsetSeconds,
                    text: segment.text
                ))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: テストを実行してすべて通ることを確認**

```bash
swift test --filter AudioChunkerTests
```

Expected: PASS (8 tests)

- [ ] **Step 5: コミット**

```bash
git add Sources/TeamsAutoRecorder/Transcription/Audio/AudioChunker.swift \
        Tests/TeamsAutoRecorderTests/AudioChunkerTests.swift
git commit -m "feat(transcription): add AudioChunker for WAV chunk reading and segment merging"
```

---

### Task 3: WhisperInferencing プロトコル変更 + DefaultWhisperInferencer チャンク推論 + WhisperKitTranscriber から AudioNormalizer を除去

**Files:**
- Modify: `Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`
- Modify: `Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift`
- Modify: `Sources/TeamsAutoRecorder/App/Orchestrator.swift`
- Modify: `Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift`

Note: これらの変更はプロトコル適合制約で相互に依存するため、一括でコミットする。

- [ ] **Step 1: 失敗するテスト変更を書く（コンパイルエラーを意図的に起こす）**

`Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift` 末尾の `FakeWhisperInferencer` を変更する:

```swift
// 変更前
private struct FakeWhisperInferencer: WhisperInferencing {
    var error: Error?

    func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment] {
        if let error { throw error }
        return [TranscriptSegment(start: 0, end: 1, text: "hello world")]
    }
}

// 変更後
private struct FakeWhisperInferencer: WhisperInferencing {
    var error: Error?

    func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment] {
        if let error { throw error }
        return [TranscriptSegment(start: 0, end: 1, text: "hello world")]
    }
}
```

- [ ] **Step 2: コンパイルエラーを確認**

```bash
swift test --filter WhisperKitTranscriberTests 2>&1 | head -20
```

Expected: compile error — `FakeWhisperInferencer` が `WhisperInferencing` プロトコルに適合しない。

- [ ] **Step 3: WhisperInferencing プロトコルを更新する**

`Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift` を変更する。

`WhisperInferencing` プロトコル（samples → audioURL）:
```swift
// 変更前
public protocol WhisperInferencing {
    func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment]
}

// 変更後
public protocol WhisperInferencing {
    func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment]
}
```

`WhisperTranscriberError` から `audioNormalizationFailed` を削除:
```swift
// 変更前
public enum WhisperTranscriberError: Error {
    case modelLoadFailed(String)
    case audioNormalizationFailed(String)
    case inferenceFailed(String)
}

// 変更後
public enum WhisperTranscriberError: Error {
    case modelLoadFailed(String)
    case inferenceFailed(String)
}
```

`WhisperKitTranscriber` から `normalizer` を削除して `transcribe` を更新する。クラス全体を以下で置き換える:

```swift
public final class WhisperKitTranscriber: AudioTranscribing {
    private let modelName: String
    private let modelManager: WhisperModelManaging
    private let inferencer: WhisperInferencing

    public init(
        modelName: String = "small",
        modelManager: WhisperModelManaging,
        inferencer: WhisperInferencing
    ) {
        self.modelName = modelName
        self.modelManager = modelManager
        self.inferencer = inferencer
    }

    public func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput {
        let modelURL: URL
        do {
            modelURL = try await modelManager.resolveModel(named: modelName)
        } catch {
            throw WhisperTranscriberError.modelLoadFailed(String(describing: error))
        }

        do {
            let segments = try await inferencer.transcribe(audioURL: audioURL, modelPath: modelURL)
            let fullText = segments
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TranscriptOutput(sessionID: sessionID, fullText: fullText, segments: segments)
        } catch {
            throw WhisperTranscriberError.inferenceFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: DefaultWhisperInferencer を書き換える**

`Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift` を以下の内容で置き換える:

```swift
import AVFoundation
import Foundation
import WhisperKit

public final class DefaultWhisperInferencer: WhisperInferencing {
    public init() {}

    public func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment] {
        let whisper = try await WhisperKit(modelFolder: modelPath.path)
        let options = DecodingOptions(language: "ja", skipSpecialTokens: true)

        let chunker = AudioChunker()
        let chunkInfos = try chunker.chunks(from: audioURL)
        guard !chunkInfos.isEmpty else { return [] }

        var chunkResults: [(info: AudioChunkInfo, segments: [TranscriptSegment])] = []
        for chunkInfo in chunkInfos {
            let result = try await whisper.transcribe(audioArray: chunkInfo.samples, decodeOptions: options)
            let segments = result.flatMap { item in
                item.segments.compactMap { segment -> TranscriptSegment? in
                    let cleaned = Self.sanitizeSegmentText(segment.text)
                    guard !cleaned.isEmpty else { return nil }
                    return TranscriptSegment(
                        start: Double(segment.start),
                        end: Double(segment.end),
                        text: cleaned
                    )
                }
            }
            chunkResults.append((info: chunkInfo, segments: segments))
        }

        return AudioChunker.mergeSegments(
            chunks: chunkResults,
            overlapSeconds: chunker.overlapSeconds
        )
    }

    static func sanitizeSegmentText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: AppBootstrap の初期化を更新する**

`Sources/TeamsAutoRecorder/App/Orchestrator.swift` の `makeDefaultOrchestrator` 内を変更する:

```swift
// 変更前
let transcriber = WhisperKitTranscriber(
    modelManager: modelManager,
    normalizer: AudioNormalizer(),
    inferencer: DefaultWhisperInferencer()
)

// 変更後
let transcriber = WhisperKitTranscriber(
    modelManager: modelManager,
    inferencer: DefaultWhisperInferencer()
)
```

- [ ] **Step 6: WhisperKitTranscriberTests を更新する**

`Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift` を次の通り変更する。

`FakeNormalizer` を削除する（ファイルから `struct FakeNormalizer: AudioNormalizing { ... }` を消す）。

`testTranscribeClassifiesNormalizationError` テスト関数を丸ごと削除する。

各テスト内の `WhisperKitTranscriber(...)` から `normalizer: FakeNormalizer()` 引数を削除する。

`testTranscribeBuildsTranscriptFromInferenceResult`:
```swift
let transcriber = WhisperKitTranscriber(
    modelName: "medium",
    modelManager: FakeModelManager(),
    inferencer: FakeWhisperInferencer()
)
```

`testTranscribeClassifiesModelResolutionError`:
```swift
let transcriber = WhisperKitTranscriber(
    modelName: "medium",
    modelManager: FakeModelManager(error: StubError.forced),
    inferencer: FakeWhisperInferencer()
)
```

`testTranscribeClassifiesInferenceError`:
```swift
let transcriber = WhisperKitTranscriber(
    modelName: "medium",
    modelManager: FakeModelManager(),
    inferencer: FakeWhisperInferencer(error: StubError.forced)
)
```

- [ ] **Step 7: テストを実行してすべて通ることを確認**

```bash
swift test --filter WhisperKitTranscriberTests
```

Expected: PASS (3 tests — normalization test は削除済み)

- [ ] **Step 8: コミット**

```bash
git add Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift \
        Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift \
        Sources/TeamsAutoRecorder/App/Orchestrator.swift \
        Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift
git commit -m "feat(transcription): replace AudioNormalizer with chunked WAV inference"
```

---

### Task 4: AudioNormalizer と AudioNormalizing を削除する

**Files:**
- Delete: `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizer.swift`
- Delete: `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizing.swift`
- Delete: `Tests/TeamsAutoRecorderTests/AudioNormalizerTests.swift`

- [ ] **Step 1: ファイルを削除する**

```bash
rm Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizer.swift
rm Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizing.swift
rm Tests/TeamsAutoRecorderTests/AudioNormalizerTests.swift
```

- [ ] **Step 2: ビルドが通ることを確認する**

```bash
swift build 2>&1 | grep "error:" | head -20
```

Expected: 出力なし（エラーゼロ）。`AudioNormalizer` / `AudioNormalizing` / `NormalizedAudio` を参照しているコードが残っていないこと。

- [ ] **Step 3: テストを実行して通ることを確認する**

```bash
swift test
```

Expected: PASS（AudioNormalizerTests の3テストが消えた分だけテスト数が減る）。

- [ ] **Step 4: コミット**

```bash
git add -A
git commit -m "refactor(transcription): delete AudioNormalizer"
```

---

### Task 5: E2ESmokeTests を更新し、全テストが通ることを確認する

**Files:**
- Modify: `Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift:40,80`

- [ ] **Step 1: E2ESmokeTests の .raw 参照を .wav に変更する**

`Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift` の2箇所を変更する。

40行目:
```swift
// 変更前
XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.raw").path))
// 変更後
XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.wav").path))
```

80行目:
```swift
// 変更前
XCTAssertTrue(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.raw").path))
// 変更後
XCTAssertTrue(FileManager.default.fileExists(atPath: temp.appendingPathComponent("session-0-mixed.wav").path))
```

- [ ] **Step 2: 全テストを実行する**

```bash
swift test
```

Expected: PASS（全テスト通過）。出力に `failed` が含まれていないこと。

- [ ] **Step 3: コミット**

```bash
git add Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift
git commit -m "test(e2e): update artifact filename from .raw to .wav"
```

---

## 補足: 録音中のメモリ蓄積について

本プランは以下を達成する:
- **音声ファイルサイズ**: テキスト比 75% 削減（460MB → 約 230MB）
- **推論時メモリ**: 1時間音声全量 → 5分チャンク × 1本（常時 ~38MB）

録音中の `RealtimeAudioMixer.mixedSamples: [Float]` は引き続きメモリに蓄積される（1時間 ≈ 230MB）。これを逐次ファイル書き込みに変えるには `RealtimeAudioMixer` と `LiveCaptureSession` プロトコルの変更が必要であり、別のリファクタリングとして切り出す。
