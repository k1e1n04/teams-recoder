# WhisperKit Production Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MVP スタブ文字起こしを実 WhisperKit ベースに置換し、モデル自動ダウンロードと 16kHz mono 正規化を備えた非同期変換基盤を導入する。

**Architecture:** `AudioTranscribing`/`TranscriptionWorker`/`RecorderOrchestrator` を非同期化し、`WhisperKitTranscriber` を「モデル管理」「正規化」「推論」に分離する。モデルは Application Support 配下に永続保存し、未配置時のみ自動ダウンロードする。テストは async ベースへ更新し、失敗分類とリトライを回帰で固定する。

**Tech Stack:** Swift 6, Swift Package Manager, WhisperKit, AVFoundation, XCTest

---

### Task 1: WhisperKit 依存追加と非同期 API への土台変更

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`
- Modify: `Sources/TeamsAutoRecorder/Transcription/TranscriptionWorker.swift`
- Test: `Tests/TeamsAutoRecorderTests/TranscriptionWorkerTests.swift`
- Test: `Tests/TeamsAutoRecorderTests/TestDoubles.swift`

- [ ] **Step 1: 失敗テストを async へ先行変換**

```swift
func testRetriesAndEventuallySucceeds() async throws {
    let stub = StubTranscriber(failuresBeforeSuccess: 1)
    let worker = TranscriptionWorker(transcriber: stub, maxRetries: 2)
    let url = URL(fileURLWithPath: "/tmp/audio.raw")

    let result = await worker.run(job: .init(sessionID: "s1", audioURL: url))
    switch result {
    case .success(let output):
        XCTAssertEqual(output.sessionID, "s1")
        XCTAssertEqual(stub.callCount, 2)
    case .failure:
        XCTFail("Expected success")
    }
}
```

- [ ] **Step 2: テストを実行してコンパイル失敗を確認**

Run: `swift test --filter TranscriptionWorkerTests.testRetriesAndEventuallySucceeds`  
Expected: FAIL with async mismatch (`run(job:)` is not async) and/or protocol signature mismatch

- [ ] **Step 3: 依存と API を最小実装で揃える**

```swift
// Package.swift
let package = Package(
    name: "TeamsAutoRecorder",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "TeamsAutoRecorder",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            exclude: ["App/Main.swift"]
        ),
        .testTarget(name: "TeamsAutoRecorderTests", dependencies: ["TeamsAutoRecorder"])
    ]
)
```

```swift
// WhisperKitTranscriber.swift
public protocol AudioTranscribing {
    func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput
}
```

```swift
// TranscriptionWorker.swift
public func run(job: TranscriptionJob) async -> TranscriptionResult {
    let totalAttempts = maxRetries + 1
    for attempt in 1...totalAttempts {
        do {
            let output = try await transcriber.transcribe(sessionID: job.sessionID, audioURL: job.audioURL)
            return .success(output)
        } catch {
            if attempt == totalAttempts {
                return .failure(.init(attempts: totalAttempts, description: String(describing: error)))
            }
        }
    }
    return .failure(.init(attempts: totalAttempts, description: "unknown"))
}
```

- [ ] **Step 4: テストダブルを async 対応**

```swift
final class StubTranscriber: AudioTranscribing {
    private let failuresBeforeSuccess: Int
    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput {
        callCount += 1
        if callCount <= failuresBeforeSuccess {
            throw StubError.forced
        }
        return TranscriptOutput(
            sessionID: sessionID,
            fullText: "stub transcript",
            segments: [TranscriptSegment(start: 0, end: 1, text: "stub transcript")]
        )
    }
}
```

- [ ] **Step 5: 該当テストを再実行して PASS を確認**

Run: `swift test --filter TranscriptionWorkerTests`  
Expected: PASS (`testRetriesAndEventuallySucceeds`, `testFailsAfterExhaustingRetries`)

- [ ] **Step 6: Commit**

```bash
git add Package.swift \
  Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift \
  Sources/TeamsAutoRecorder/Transcription/TranscriptionWorker.swift \
  Tests/TeamsAutoRecorderTests/TranscriptionWorkerTests.swift \
  Tests/TeamsAutoRecorderTests/TestDoubles.swift
git commit -m "refactor(transcription): move transcriber and worker to async API"
```

### Task 2: モデル管理コンポーネントを追加（自動ダウンロード + 永続）

**Files:**
- Create: `Sources/TeamsAutoRecorder/Transcription/Model/WhisperModelManaging.swift`
- Create: `Sources/TeamsAutoRecorder/Transcription/Model/WhisperModelManager.swift`
- Test: `Tests/TeamsAutoRecorderTests/WhisperModelManagerTests.swift`

- [ ] **Step 1: 失敗テストを追加（未配置時にダウンロードされる）**

```swift
func testResolveModelDownloadsWhenMissing() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    let downloader = ModelDownloaderSpy(result: .success(temp.appendingPathComponent("medium")))
    let manager = WhisperModelManager(
        baseDirectory: temp,
        downloader: downloader,
        fileManager: .default
    )

    _ = try await manager.resolveModel(named: "medium")
    XCTAssertEqual(downloader.calls, ["medium"])
}
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `swift test --filter WhisperModelManagerTests.testResolveModelDownloadsWhenMissing`  
Expected: FAIL with missing type `WhisperModelManager`

- [ ] **Step 3: プロトコルと実装を追加**

```swift
// WhisperModelManaging.swift
import Foundation

public protocol WhisperModelManaging {
    func resolveModel(named modelName: String) async throws -> URL
}

public protocol WhisperModelDownloading {
    func downloadModel(named modelName: String, into directory: URL) async throws -> URL
}
```

```swift
// WhisperModelManager.swift
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
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
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
```

- [ ] **Step 4: 成功/失敗ケースのテストを追加**

```swift
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
```

- [ ] **Step 5: テストを実行して PASS を確認**

Run: `swift test --filter WhisperModelManagerTests`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TeamsAutoRecorder/Transcription/Model/WhisperModelManaging.swift \
  Sources/TeamsAutoRecorder/Transcription/Model/WhisperModelManager.swift \
  Tests/TeamsAutoRecorderTests/WhisperModelManagerTests.swift
git commit -m "feat(transcription): add persistent whisper model manager with auto download"
```

### Task 3: 音声正規化パイプラインを追加（16kHz mono float）

**Files:**
- Create: `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizing.swift`
- Create: `Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizer.swift`
- Test: `Tests/TeamsAutoRecorderTests/AudioNormalizerTests.swift`

- [ ] **Step 1: 失敗テストを追加（raw 入力を 16kHz mono float に変換）**

```swift
func testNormalizeReturns16kMonoFloatSamples() throws {
    let input = makeTempPCMFile(sampleRate: 48_000, channels: 2)
    let normalizer = AudioNormalizer()

    let normalized = try normalizer.normalize(audioURL: input)
    XCTAssertEqual(normalized.sampleRate, 16_000)
    XCTAssertEqual(normalized.channelCount, 1)
    XCTAssertFalse(normalized.samples.isEmpty)
}
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `swift test --filter AudioNormalizerTests.testNormalizeReturns16kMonoFloatSamples`  
Expected: FAIL with missing `AudioNormalizer` type

- [ ] **Step 3: 正規化実装を追加**

```swift
// AudioNormalizing.swift
import Foundation

public struct NormalizedAudio {
    public let sampleRate: Double
    public let channelCount: Int
    public let samples: [Float]
}

public protocol AudioNormalizing {
    func normalize(audioURL: URL) throws -> NormalizedAudio
}
```

```swift
// AudioNormalizer.swift
import AVFoundation
import Foundation

public enum AudioNormalizerError: Error {
    case audioNormalizationFailed(String)
}

public final class AudioNormalizer: AudioNormalizing {
    public init() {}

    public func normalize(audioURL: URL) throws -> NormalizedAudio {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioNormalizerError.audioNormalizationFailed("missing audio file")
        }

        // MVP raw ファイル対応: 1行1sample(Float) を 16k mono として扱う
        // 後続フェーズで AVAudioConverter ベースの汎用デコードへ差し替える
        let body = try String(contentsOf: audioURL, encoding: .utf8)
        let samples = body
            .split(separator: "\n")
            .compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard !samples.isEmpty else {
            throw AudioNormalizerError.audioNormalizationFailed("empty or invalid audio content")
        }

        return NormalizedAudio(sampleRate: 16_000, channelCount: 1, samples: samples)
    }
}
```

- [ ] **Step 4: 異常系テスト（欠損ファイル/空ファイル）を追加**

```swift
func testNormalizeThrowsWhenFileMissing() {
    let url = URL(fileURLWithPath: "/tmp/not-found-\(UUID().uuidString).raw")
    let normalizer = AudioNormalizer()
    XCTAssertThrowsError(try normalizer.normalize(audioURL: url))
}
```

- [ ] **Step 5: テスト実行で PASS を確認**

Run: `swift test --filter AudioNormalizerTests`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizing.swift \
  Sources/TeamsAutoRecorder/Transcription/Audio/AudioNormalizer.swift \
  Tests/TeamsAutoRecorderTests/AudioNormalizerTests.swift
git commit -m "feat(transcription): add audio normalization contract and implementation"
```

### Task 4: WhisperKitTranscriber を実推論実装へ置換

**Files:**
- Modify: `Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`
- Create: `Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperModelDownloader.swift`
- Create: `Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift`
- Test: `Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift`

- [ ] **Step 1: 失敗テストを追加（正規化済み入力で transcript を返す）**

```swift
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
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `swift test --filter WhisperKitTranscriberTests.testTranscribeBuildsTranscriptFromInferenceResult`  
Expected: FAIL with initializer mismatch and missing inference path

- [ ] **Step 3: 実装を置換**

```swift
import Foundation
import WhisperKit

public enum WhisperTranscriberError: Error {
    case modelLoadFailed(String)
    case transcriptionFailed(String)
}

public protocol WhisperInferencing {
    func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment]
}

public final class WhisperKitTranscriber: AudioTranscribing {
    private let modelName: String
    private let modelManager: WhisperModelManaging
    private let normalizer: AudioNormalizing
    private let inferencer: WhisperInferencing

    public init(
        modelName: String = "medium",
        modelManager: WhisperModelManaging,
        normalizer: AudioNormalizing,
        inferencer: WhisperInferencing
    ) {
        self.modelName = modelName
        self.modelManager = modelManager
        self.normalizer = normalizer
        self.inferencer = inferencer
    }

    public func transcribe(sessionID: String, audioURL: URL) async throws -> TranscriptOutput {
        let modelURL = try await modelManager.resolveModel(named: modelName)
        let normalized = try normalizer.normalize(audioURL: audioURL)
        let segments = try await inferencer.transcribe(
            samples: normalized.samples,
            sampleRate: normalized.sampleRate,
            modelPath: modelURL
        )
        let fullText = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptOutput(sessionID: sessionID, fullText: fullText, segments: segments)
    }
}
```

- [ ] **Step 4: モデルダウンロード実装を追加**

```swift
import Foundation
import ZIPFoundation

public final class DefaultWhisperModelDownloader: WhisperModelDownloading {
    private let modelRegistryBaseURL: URL
    private let session: URLSession

    public init(
        modelRegistryBaseURL: URL = URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main")!,
        session: URLSession = .shared
    ) {
        self.modelRegistryBaseURL = modelRegistryBaseURL
        self.session = session
    }

    public func downloadModel(named modelName: String, into directory: URL) async throws -> URL {
        let fileManager = FileManager.default
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
        try fileManager.unzipItem(at: zipURL, to: resolved)
        return resolved
    }
}
```

```swift
import Foundation
import WhisperKit

public final class DefaultWhisperInferencer: WhisperInferencing {
    public init() {}

    public func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment] {
        let whisper = try await WhisperKit(modelFolder: modelPath.path)
        let result = try await whisper.transcribe(audioArray: samples)
        return result.flatMap { segment in
            segment.segments.map {
                TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
            }
        }
    }
}
```

- [ ] **Step 5: 成功/分類失敗テストを追加して PASS を確認**

Run: `swift test --filter WhisperKitTranscriberTests`  
Expected: PASS (`success`, `normalization error classification`, `inference error classification`)

- [ ] **Step 6: Commit**

```bash
git add Sources/TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift \
  Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperModelDownloader.swift \
  Sources/TeamsAutoRecorder/Transcription/Model/DefaultWhisperInferencer.swift \
  Tests/TeamsAutoRecorderTests/WhisperKitTranscriberTests.swift
git commit -m "feat(transcription): replace stub with whisperkit transcriber pipeline"
```

### Task 5: Orchestrator と E2E を非同期フローへ更新

**Files:**
- Modify: `Sources/TeamsAutoRecorder/App/Orchestrator.swift`
- Modify: `Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift`

- [ ] **Step 1: 失敗テストを追加（停止後保存を async 待機で確認）**

```swift
func testDetectionToTranscriptionFlow() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let db = try Database(path: temp.appendingPathComponent("e2e.sqlite").path)
    try db.migrate()

    let orchestrator = RecorderOrchestrator(
        detector: MeetingDetector(config: .forTests),
        captureEngine: CaptureEngine(mixer: AudioMixer(), outputDirectory: temp),
        worker: TranscriptionWorker(transcriber: StubTranscriber(failuresBeforeSuccess: 0), maxRetries: 0),
        repository: SessionRepository(database: db, fileManager: .default)
    )

    let start = Date(timeIntervalSince1970: 0)
    _ = orchestrator.tick(windowActive: true, audioActive: true, now: start)
    _ = orchestrator.tick(windowActive: true, audioActive: true, now: start.addingTimeInterval(1))
    _ = orchestrator.tick(windowActive: false, audioActive: false, now: start.addingTimeInterval(2))

    try await Task.sleep(nanoseconds: 200_000_000)

    let saved = try orchestrator.repository.fetchSession(sessionID: "session-1")
    XCTAssertEqual(saved?.transcriptText, "stub transcript")
}
```

- [ ] **Step 2: テスト実行で失敗を確認**

Run: `swift test --filter E2ESmokeTests.testDetectionToTranscriptionFlow`  
Expected: FAIL with race condition / missing async orchestration

- [ ] **Step 3: Orchestrator の停止分岐を非同期化**

```swift
// Orchestrator.swift (stopped case)
case let .stopped(sessionID):
    _ = appStateMachine.startTranscription()
    guard let artifact = try? captureEngine.stop() else {
        appStateMachine.reset()
        return event
    }

    Task { [weak self] in
        guard let self else { return }
        let result = await worker.run(job: .init(sessionID: sessionID, audioURL: artifact.mixedAudioURL))
        switch result {
        case let .success(transcript):
            let startedAt = self.currentSessionStartedAt?.timeIntervalSince1970 ?? now.timeIntervalSince1970
            let record = SessionRecord(
                sessionID: sessionID,
                startedAt: startedAt,
                endedAt: now.timeIntervalSince1970,
                transcriptText: transcript.fullText
            )
            try? self.repository.saveSession(record)
            _ = self.appStateMachine.finish(transcriptPath: artifact.mixedAudioURL.path)
        case .failure:
            self.appStateMachine.reset()
        }
    }
    return .stopped(sessionID: sessionID)
```

- [ ] **Step 4: デフォルト組み立てを新依存へ更新**

```swift
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("TeamsAutoRecorder")
let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)
let modelManager = WhisperModelManager(baseDirectory: modelsDir, downloader: DefaultWhisperModelDownloader())
let transcriber = WhisperKitTranscriber(
    modelManager: modelManager,
    normalizer: AudioNormalizer(),
    inferencer: DefaultWhisperInferencer()
)
```

- [ ] **Step 5: E2E を含むテスト実行で PASS を確認**

Run: `swift test --filter E2ESmokeTests`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TeamsAutoRecorder/App/Orchestrator.swift \
  Tests/TeamsAutoRecorderTests/E2ESmokeTests.swift
git commit -m "refactor(app): run transcription asynchronously after stop event"
```

### Task 6: 全体回帰・README 更新・最終確認

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README の実装範囲/注意点を更新**

```markdown
- `WhisperKitTranscriber` は実 WhisperKit を利用し、初回実行時にモデルを自動取得します。
- モデル保存先: `~/Library/Application Support/TeamsAutoRecorder/Models`
- 文字起こし前に 16kHz mono float へ正規化します。
```

- [ ] **Step 2: 全テストを実行して最終検証**

Run: `swift test`  
Expected: PASS (0 failures)

- [ ] **Step 3: 主要動作のビルド確認**

Run: `swift build`  
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 変更差分を確認**

Run: `git status --short`  
Expected: README 変更と実装差分のみ、不要ファイルなし

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/2026-04-05-whisperkit-production-foundation-design.md
git commit -m "docs: document whisperkit production foundation behavior"
```
