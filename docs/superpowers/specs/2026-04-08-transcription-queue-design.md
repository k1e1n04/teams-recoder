# 文字起こしキュー設計

**日付:** 2026-04-08  
**対象:** 文字起こし中に次の録音が始まった場合の録音取りこぼし問題の解決

## 背景・課題

現在の実装では、ミーティング終了後に `finishSession()` が `worker.run()` を `await` するため、メインループが文字起こし完了まで完全にブロックされる。連続会議が多い環境では、文字起こし中に始まった次のミーティングの録音が丸ごと失われる。

## 設計方針

文字起こしをメインの録音ループから切り離し、専用の `TranscriptionQueue` actor に委譲する。録音が終わり次第すぐに `idle` に戻ることで、次の録音を即座に開始できる。

---

## セクション1：State Machine の簡略化

### 変更前
```
idle → recording → transcribing → completed → idle
```

### 変更後
```
idle → recording → idle
```

`AppState` から `transcribing` と `completed` ケースを削除する。`AppStateMachine` の `startTranscription()` と `finish()` メソッドも削除する。状態機械は録音の開始・停止のみを管理する。

---

## セクション2：TranscriptionQueue actor

### 責務
文字起こしジョブを受け取り、1件ずつ順番に処理する。

### インターフェース

```swift
actor TranscriptionQueue {
    struct Job {
        let sessionID: String
        let audioURL: URL
        let startedAt: TimeInterval
        let endedAt: TimeInterval
    }

    var onQueueChanged: (@MainActor (Int) -> Void)?

    init(
        worker: TranscriptionWorker,
        repository: SessionRepository,
        artifactStore: SessionAudioArtifactStore?
    )

    func enqueue(_ job: Job)
    var pendingCount: Int { get }
}
```

### 内部動作

```swift
private var jobs: [Job] = []
private var isProcessing = false

func enqueue(_ job: Job) {
    jobs.append(job)
    await MainActor.run { onQueueChanged?(jobs.count) }
    if !isProcessing {
        Task { await processNext() }
    }
}

private func processNext() async {
    isProcessing = true
    while !jobs.isEmpty {
        let job = jobs.removeFirst()
        await MainActor.run { onQueueChanged?(jobs.count) }
        await process(job)
    }
    isProcessing = false
    await MainActor.run { onQueueChanged?(0) }
}
```

`process()` の実装は現在の `finishSession` 後半（`worker.run()` → 成功/失敗の `SessionRecord` 保存 → アーティファクト削除）をそのまま移植する。

### 制約
アプリ終了時にキューに残っているジョブは消える（今回は許容範囲とする）。

---

## セクション3：RecorderOrchestrator の変更

### finishSession の簡略化

`finishSession` は引き続き `async` だが、`worker.run()` の長い待機がなくなり、ほぼ即座に返る。

```swift
// 変更前: async、worker.run() で数分ブロック
private func finishSession(sessionID: String, now: Date) async -> SessionFinishOutcome

// 変更後: async だが即リターン（actor の enqueue を await するだけ）
private func finishSession(sessionID: String, now: Date) async {
    guard let artifact = try? captureEngine.stop() else {
        appStateMachine.reset()
        currentSessionStartedAt = nil
        return
    }
    let job = TranscriptionQueue.Job(
        sessionID: sessionID,
        audioURL: artifact.mixedAudioURL,
        startedAt: currentSessionStartedAt ?? now.timeIntervalSince1970,
        endedAt: now.timeIntervalSince1970
    )
    await transcriptionQueue.enqueue(job)  // actor 呼び出し、ほぼ即座に完了
    appStateMachine.reset()
    currentSessionStartedAt = nil
}
```

### tick() の変更
- `finishSession` は `async` を維持するが待機時間がマイクロ秒レベルになるためメインループは実質ブロックされない
- `.stopped` ケースの `onTranscriptionStarted` コールバックを削除する
- `tick()` の戻り値型 `MeetingDetectorEvent?` は維持する

---

## セクション4：UI への影響

### ステータス表示

| 状態 | 表示 |
|---|---|
| 録音中 | "録音中" |
| アイドル、キュー空 | "待機中" |
| アイドル、キュー1件以上 | "文字起こし中 (残 N 件)" |

### 実装

`TranscriptionQueue.onQueueChanged` コールバックを `RuntimeController` が受け取り `statusText` を更新する。

```swift
transcriptionQueue.onQueueChanged = { [weak self] count in
    guard let self else { return }
    if count == 0 {
        self.statusText = "待機中"
    } else {
        self.statusText = "文字起こし中 (残 \(count) 件)"
    }
}
```

---

## 影響ファイル一覧

| ファイル | 変更種別 |
|---|---|
| `Sources/TeamsAutoRecorder/App/AppState.swift` | 変更（状態削減） |
| `Sources/TeamsAutoRecorder/App/Orchestrator.swift` | 変更（finishSession 簡略化） |
| `Sources/TeamsAutoRecorder/Transcription/TranscriptionQueue.swift` | 新規作成 |
| `Sources/TeamsAutoRecorder/App/Main.swift` | 変更（UI ステータス更新） |
| `Tests/TeamsAutoRecorderTests/AppStateTests.swift` | 変更（状態削減に合わせてテスト更新） |

---

## 非機能要件

- Whisper は同時に1インスタンスのみ実行（リソース安全）
- 録音は文字起こしの完了を待たずに即座に再開可能
- アプリ終了時の未処理ジョブは今回スコープ外
