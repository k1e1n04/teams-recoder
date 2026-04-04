# WhisperKit Production Foundation Design

## Goal
MVP のスタブ `WhisperKitTranscriber` を実運用に近い土台へ置換し、実 WhisperKit 連携・モデル自動ダウンロード/永続管理・音声正規化を導入する。

## Confirmed Decisions
- 実装方式は一括置換（案2）
- `AudioTranscribing` は `async throws` に変更
- モデルは自動ダウンロードあり
- モデル保存先は永続（`~/Library/Application Support/TeamsAutoRecorder/Models`）
- 現フェーズでは権限実装と ScreenCaptureKit/AVFoundation 本実装は対象外

## Scope
- `WhisperKitTranscriber` を実 WhisperKit 呼び出しへ置換
- モデル管理コンポーネントを追加（解決、ダウンロード、検証、ロード）
- 音声正規化パイプラインを追加（16kHz mono float）
- `TranscriptionWorker` と関連呼び出し側を `async` 化
- テストを非同期化し、主要失敗パスをカバー

## Non-goals
- Screen Recording / Microphone 権限の本実装
- ScreenCaptureKit / AVFoundation の本実装改善
- 高度 DSP（ノイズ除去、AGC、話者分離）
- 外部送信やクラウド同期

## Architecture
- `WhisperKitTranscriber`: 推論のオーケストレーション（入力検証、正規化、推論、整形）
- `WhisperModelManager`（新規）: モデルの存在確認、未配置時ダウンロード、永続先への配置、ロード
- `AudioNormalizer`（新規）: 入力音声を Whisper 前提フォーマットへ変換
- `TranscriptionWorker`: リトライ管理と結果の正規化（既存責務を維持）
- `RecorderOrchestrator`: 停止後に `Task` で非同期文字起こしを実行し、成功時保存・失敗時リセット

## Data Flow
1. `RecorderOrchestrator.tick` が `stopped(sessionID)` を受ける
2. 録音停止して `mixedAudioURL` を取得
3. `Task` で `await TranscriptionWorker.run(job:)` を起動
4. `TranscriptionWorker` が `await WhisperKitTranscriber.transcribe(...)` を実行（失敗時リトライ）
5. `WhisperKitTranscriber` が `WhisperModelManager` でモデル解決/ロード
6. `AudioNormalizer` が入力音声を 16kHz mono float へ正規化
7. WhisperKit 推論結果を `TranscriptOutput` に変換
8. 成功時は `SessionRepository.saveSession`、失敗時は state reset と失敗記録

## Model Management
- 既定モデル: `medium`
- 保存先: `~/Library/Application Support/TeamsAutoRecorder/Models`
- 振る舞い:
  - ローカルに有効モデルがあれば再利用
  - なければダウンロード
  - ダウンロード失敗時は `modelDownloadFailed`
  - 読み込み失敗時は `modelLoadFailed`
- 将来拡張:
  - モデルバージョン固定
  - キャッシュクリア機能
  - 複数モデル選択

## Audio Normalization
- 目的: 入力フォーマット差異を吸収し Whisper への投入を安定化
- 変換:
  - サンプルレート 16kHz
  - モノラル
  - `Float32` waveform
- 失敗条件:
  - ファイル欠損
  - 未対応/破損フォーマット
  - デコード不可能
- 失敗時エラー: `audioNormalizationFailed`

## Error Handling
- エラー分類:
  - `modelDownloadFailed`
  - `modelLoadFailed`
  - `audioNormalizationFailed`
  - `transcriptionFailed`
- リトライ対象:
  - 一時的 I/O 失敗
  - 推論失敗
- リトライ非対象:
  - 入力不正や破損など恒久エラー
- 最終失敗時は `TranscriptionFailure.description` に分類と詳細を保持

## Testing Strategy
- `TranscriptionWorkerTests`:
  - 非同期リトライ成功
  - 非同期リトライ失敗
- `WhisperKitTranscriberTests`（新規）:
  - モデル未配置時にダウンロード経由で推論成功
  - 正規化失敗を適切分類
  - 推論失敗を適切分類
- `RecorderOrchestrator` 関連:
  - 停止イベント後に非同期文字起こし成功で保存される
  - 失敗時に state reset される

## Risks and Mitigations
- リスク: 初回モデルダウンロード時間が長い
  - 対策: 進行状態ログとリトライ方針を明示
- リスク: 非同期化によるテスト不安定化
  - 対策: `XCTest` の async テストへ全面移行し待機条件を明示
- リスク: 音声フォーマットばらつき
  - 対策: 正規化層で入力契約を統一しエラー分類を固定

