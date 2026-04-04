# Teams Auto Recorder MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teams会議を誤検知最小で自動検知し、会議終了後に WhisperKit (medium) でトランスクリプトを生成する macOS メニューバーアプリMVPを作る。

**Architecture:** 検知・録音・文字起こし・保存を明確に分離する。検知は UI状態 + 音声活動 のAND判定を採用し、録音はシステム音声とマイクをセッション単位で管理する。停止後にのみバッチ文字起こしを実行する。

**Tech Stack:** Swift, SwiftUI/AppKit (menu bar), ScreenCaptureKit, AVFoundation, WhisperKit, SQLite, XCTest

---

## File Structure
- Create: `TeamsAutoRecorder/App/Main.swift`（アプリ起動・依存構築）
- Create: `TeamsAutoRecorder/App/AppState.swift`（待機/録音/変換/完了状態）
- Create: `TeamsAutoRecorder/Detector/MeetingDetector.swift`（開始終了判定）
- Create: `TeamsAutoRecorder/Detector/TeamsWindowSignalProvider.swift`（Teams UIシグナル）
- Create: `TeamsAutoRecorder/Detector/TeamsAudioSignalProvider.swift`（Teams音声活動シグナル）
- Create: `TeamsAutoRecorder/Capture/CaptureEngine.swift`（録音開始停止制御）
- Create: `TeamsAutoRecorder/Capture/AudioMixer.swift`（Teams+Micミックス/同期）
- Create: `TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`（lumina-whisper流用）
- Create: `TeamsAutoRecorder/Transcription/TranscriptionWorker.swift`（停止後ジョブ実行）
- Create: `TeamsAutoRecorder/Storage/Database.swift`（SQLite接続）
- Create: `TeamsAutoRecorder/Storage/SessionRepository.swift`（セッション保存）
- Create: `TeamsAutoRecorder/UI/MenuBarController.swift`（メニューバー表示・通知）
- Create: `TeamsAutoRecorder/Permissions/PermissionCoordinator.swift`（Screen/Mic権限）
- Test: `TeamsAutoRecorderTests/MeetingDetectorTests.swift`
- Test: `TeamsAutoRecorderTests/TranscriptionWorkerTests.swift`
- Test: `TeamsAutoRecorderTests/SessionRepositoryTests.swift`

### Task 1: Project Scaffold + App State
**Files:**
- Create: `TeamsAutoRecorder/App/Main.swift`
- Create: `TeamsAutoRecorder/App/AppState.swift`
- Test: `TeamsAutoRecorderTests/AppStateTests.swift`

- [ ] Step 1: AppState の failing test を書く
- [ ] Step 2: `xcodebuild test -scheme TeamsAutoRecorder -only-testing:TeamsAutoRecorderTests/AppStateTests` を実行して失敗確認
- [ ] Step 3: AppState enum/state transition の最小実装を書く
- [ ] Step 4: 同テストを再実行して成功確認
- [ ] Step 5: commit (`feat: add app state model for recorder lifecycle`)

### Task 2: Permission Gate
**Files:**
- Create: `TeamsAutoRecorder/Permissions/PermissionCoordinator.swift`
- Modify: `TeamsAutoRecorder/App/Main.swift`
- Test: `TeamsAutoRecorderTests/PermissionCoordinatorTests.swift`

- [ ] Step 1: 権限状態判定の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: Screen Recording / Microphone 判定と設定誘導処理を実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`feat: add permission coordinator for screen and mic access`)

### Task 3: MeetingDetector (AND判定)
**Files:**
- Create: `TeamsAutoRecorder/Detector/MeetingDetector.swift`
- Create: `TeamsAutoRecorder/Detector/TeamsWindowSignalProvider.swift`
- Create: `TeamsAutoRecorder/Detector/TeamsAudioSignalProvider.swift`
- Test: `TeamsAutoRecorderTests/MeetingDetectorTests.swift`

- [ ] Step 1: 開始条件AND判定・停止遅延の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: N/M/K/T/最短録音時間付き state machine を実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`feat: implement conservative teams meeting detector`)

### Task 4: CaptureEngine (Teams + Mic)
**Files:**
- Create: `TeamsAutoRecorder/Capture/CaptureEngine.swift`
- Create: `TeamsAutoRecorder/Capture/AudioMixer.swift`
- Test: `TeamsAutoRecorderTests/CaptureEngineTests.swift`

- [ ] Step 1: start/stop とチャンク保存の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: ScreenCaptureKit + AVFoundation で同時収録を最小実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`feat: add capture engine for teams and microphone audio`)

### Task 5: WhisperKit 一括文字起こし
**Files:**
- Create: `TeamsAutoRecorder/Transcription/WhisperKitTranscriber.swift`
- Create: `TeamsAutoRecorder/Transcription/TranscriptionWorker.swift`
- Test: `TeamsAutoRecorderTests/TranscriptionWorkerTests.swift`

- [ ] Step 1: 変換ジョブ成功/失敗/再試行の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: `medium` 既定の WhisperKit バッチ変換を実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`feat: add post-meeting whisperkit transcription worker`)

### Task 6: Storage + Export
**Files:**
- Create: `TeamsAutoRecorder/Storage/Database.swift`
- Create: `TeamsAutoRecorder/Storage/SessionRepository.swift`
- Test: `TeamsAutoRecorderTests/SessionRepositoryTests.swift`

- [ ] Step 1: セッション保存・検索の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: SQLite スキーマ（sessions, transcript_jobs, transcript_segments）を実装
- [ ] Step 4: `Transcript.txt` / `Transcript.json` 出力実装
- [ ] Step 5: テスト成功確認
- [ ] Step 6: commit (`feat: add local persistence and transcript export`)

### Task 7: Menu Bar UI + Notification
**Files:**
- Create: `TeamsAutoRecorder/UI/MenuBarController.swift`
- Modify: `TeamsAutoRecorder/App/Main.swift`
- Test: `TeamsAutoRecorderTests/MenuBarControllerTests.swift`

- [ ] Step 1: 状態表示と通知発火の failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: メニューバー状態と無音通知を実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`feat: add menu bar status and silent notifications`)

### Task 8: End-to-End Smoke
**Files:**
- Create: `TeamsAutoRecorderTests/E2ESmokeTests.swift`

- [ ] Step 1: 擬似シグナルで E2E failing test を書く
- [ ] Step 2: テスト失敗確認
- [ ] Step 3: 起動→検知→録音→停止→変換完了の結線を実装
- [ ] Step 4: テスト成功確認
- [ ] Step 5: commit (`test: add mvp e2e smoke coverage`)

## Self-Review
- Spec coverage: 検知/録音/変換/保存/通知/権限/誤検知抑制を全タスクに対応付け済み
- Placeholder scan: TBD/TODO なし
- Type consistency: コンポーネント命名を統一（Detector/Capture/Transcription/Storage/UI）
