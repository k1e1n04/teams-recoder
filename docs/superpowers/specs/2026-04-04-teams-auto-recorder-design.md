# Teams Auto Recorder Design

## Goal
Teams会議を自動検知し、Teams標準録音機能を使わずに macOS デスクトップアプリ側で録音し、会議終了後に WhisperKit (medium) で文字起こしを行う。

## Confirmed Product Decisions
- 最優先: 誤検知を最小化
- 録音対象: 相手 + 自分
- 文字起こし: 会議後に一括変換
- 開始通知: 通知あり（無音）
- 既定モデル: WhisperKit `medium`

## Architecture
- `MeetingDetector`: 会議開始/終了の判定（UI状態 + 音声活動）
- `CaptureEngine`: Teams音声 + マイクの同時収録
- `TranscriptionWorker`: 停止後に WhisperKit 一括変換
- `Storage/UI`: SQLite + メニューバー状態表示

## Detection Logic
### Start (AND required)
1. UI状態シグナル
- Teams会議相当のウィンドウ状態が連続 N 秒（初期値 8 秒）

2. 音声活動シグナル
- Teams出力音声が M 秒窓で K%以上アクティブ（初期値: 12秒窓 / 70%）

両者同時成立時のみ録音開始。開始時に無音通知を 1 回表示。

### Stop
- 会議UI喪失 または Teams音声活動低下が連続 T 秒続いたら停止候補
- 最短録音時間（初期値 2 分）未満は停止遅延して誤停止を回避

### Guard Rails
- 日次誤開始上限（false-positive cap）
- 誤開始が続く場合は自動録音を一時停止し通知モードへフォールバック

## Recording and Transcription Pipeline
1. 録音開始でセッションID採番
2. Teams音声 + マイク音声を同一タイムラインで収録
3. チャンク保存でクラッシュ耐性を確保
4. 停止後にセッション音声を 16kHz mono float へ正規化
5. `WhisperKitTranscriber` へ投入し一括文字起こし
6. `Transcript.txt` / `Transcript.json` / メタデータを保存

## WhisperKit Reuse Strategy
`../lumina-whisper`（隣接リポジトリ想定）の `WhisperKitTranscriber` をベースに再利用:
- actorベースのモデルロード管理
- RMS無音判定
- ハルシネーション除去
- DecodingOptions ベースの安定推論設定

## Permissions / Compliance
- 必須権限: Screen Recording, Microphone
- 初回同意: 参加者同意・組織ポリシー順守を明示
- データ方針: ローカル保存デフォルト、外部送信OFFデフォルト

## Test Strategy
- 判定ロジックの回帰テスト（誤検知率）
- 録音同期検証（Teams + Mic）
- WhisperKit medium の性能/品質ベンチ
- E2E: 開始検知→録音→停止→変換完了通知
