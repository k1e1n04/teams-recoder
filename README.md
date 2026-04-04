# teams-recoder

Teams 会議を自動検知し、録音停止後に文字起こしを行う macOS 向け MVP の土台実装です。  
現状は Swift Package ベースで、検知・録音・変換・保存・通知の責務分離とテストを先に固めています。

## 現在の実装範囲

- `AppState` によるライフサイクル管理（待機/録音/変換/完了）
- `MeetingDetector` による保守的な開始・停止判定（UI + 音声活動の AND）
- `CaptureEngine` / `AudioMixer` による Teams 音声 + マイク音声の収録フロー
- `TranscriptionWorker` / `WhisperKitTranscriber` による停止後バッチ変換フロー
- `Database` / `SessionRepository` による SQLite 保存と `Transcript.txt` / `Transcript.json` 出力
- `MenuBarController` による状態表示とサイレント通知
- E2E スモークテスト（起動→検知→録音→停止→変換完了）

## ディレクトリ構成

```text
Sources/TeamsAutoRecorder/
  App/
  Detector/
  Capture/
  Transcription/
  Storage/
  UI/
  Permissions/

Tests/TeamsAutoRecorderTests/
docs/superpowers/
```

## セットアップ

前提:

- macOS
- Xcode 16+ または Swift 6.0+ ツールチェーン

```bash
swift --version
swift build
```

## テスト

```bash
swift test
```

## 仕様・計画

- 設計: `docs/superpowers/specs/2026-04-04-teams-auto-recorder-design.md`
- 実装計画: `docs/superpowers/plans/2026-04-04-teams-auto-recorder-mvp.md`

## 注意点

- 現在の `WhisperKitTranscriber` は MVP 土台用の最小実装です。実運用向けには実 WhisperKit 連携、モデル管理、音声正規化パイプラインの強化が必要です。
- 実際の Screen Recording / Microphone 権限、ScreenCaptureKit/AVFoundation の本実装は今後のフェーズで詰める前提です。
