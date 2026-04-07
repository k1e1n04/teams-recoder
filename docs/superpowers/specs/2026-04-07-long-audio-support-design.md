# Long Audio Support Design

**Date:** 2026-04-07  
**Status:** Approved  
**Scope:** 1時間以上の音声録音・文字起こしに対応するための設計

---

## 背景・動機

現行実装は以下の理由で長時間録音に対応していない：

1. **テキストRAWフォーマット**: 音声サンプルを `%.6f\n` 形式で保存。1時間分で約460MB以上になり、書き込み・読み込みが低速かつメモリ非効率
2. **全サンプルのメモリ蓄積**: `CaptureEngine` が録音中ずっと `[Float]` をメモリに追記し続ける
3. **一括WhisperKit推論**: 全サンプルを一度に投入するため、1時間音声ではWhisperKitモデル（約1GB）＋音声データ（約230MB）で合計1.2GB以上を常時消費

---

## 設計方針

### 決定事項

| 項目 | 決定 |
|---|---|
| 保存フォーマット | WAV（Float32, 16kHz, モノラル） |
| ディスク書き込み | 録音中に逐次書き込み（メモリ蓄積なし） |
| チャンク分割 | アプリ側で5分チャンクに分割して順次推論 |
| 中断時の挙動 | 不完全ファイルは破棄（既存クリーンアップ処理に委ねる） |
| 外部インターフェース | `AudioTranscribing` プロトコル・`TranscriptOutput` 型は変更しない |

---

## データフロー

### 変更前

```
CaptureEngine
  → [Float] をメモリに蓄積し続ける
  → 録音終了時にテキスト（%.6f\n）としてディスクへ一括書き込み

AudioNormalizer
  → テキストファイルを全量メモリ読み込み
  → 文字列パースで [Float] に変換

DefaultWhisperInferencer
  → 全サンプル ([Float]) を WhisperKit に一括投入
  → TranscriptSegment[] を返す
```

### 変更後

```
CaptureEngine
  → AVAudioFile（WAV）をオープン
  → コールバックごとに AVAudioPCMBuffer を書き込み（メモリ蓄積なし）
  → 録音終了時に close

AudioNormalizer（廃止）
  → 削除。WAV読み込み責務は WhisperInferencer に統合

DefaultWhisperInferencer
  → WAVファイルを5分チャンク（+ 30秒オーバーラップ）で読み込み
  → チャンクごとに WhisperKit.transcribe()
  → タイムスタンプをオフセット補正して結合
  → 重複セグメントを除去
  → TranscriptSegment[] を返す（インターフェース変更なし）
```

---

## 変更コンポーネント詳細

### 1. CaptureEngine

**削除するもの:**
- `teamsSamples: [Float]`
- `micSamples: [Float]`
- `chunks: [TimeInterval: TimedChunk]`
- テキスト形式での書き込みコード

**追加するもの:**
- `mixedAudioFile: AVAudioFile?` — 録音中オープンしたままにする
- 録音開始時: `AVAudioFile(forWriting:settings:)` でWAVを作成
  - フォーマット: Float32, 16kHz, モノラル
- コールバック時: ミックス計算（Teams + Mic合成）→ `AVAudioPCMBuffer` → `AVAudioFile.write(from:)`
- 録音終了時: `mixedAudioFile = nil`（closeされる）

**ミックス処理**: 既存のチャンク合成ロジックをコールバック内にインライン化する。

### 2. AudioNormalizer（廃止）

- `AudioNormalizer.swift` を削除
- `NormalizedAudio` 型も削除
- 関連するテストファイルを削除
- `WhisperKitTranscriber` からの参照を削除

### 3. DefaultWhisperInferencer

**シグネチャ変更:**

```swift
// 変更前
func transcribe(samples: [Float], sampleRate: Double, modelPath: URL) async throws -> [TranscriptSegment]

// 変更後
func transcribe(audioURL: URL, modelPath: URL) async throws -> [TranscriptSegment]
```

**チャンク分割パラメータ:**
- チャンクサイズ: 5分（5 × 60 × 16000 = 4,800,000 サンプル）
- オーバーラップ: 30秒（480,000 サンプル）
- 読み込み: `AVAudioFile` でチャンクごとに `AVAudioPCMBuffer` を読み込む

**重複除去:**
- 前チャンクのオーバーラップ範囲（最後の30秒）に含まれるセグメントは次チャンクから破棄
- 判定: `segment.startTime < chunkOffset`（オフセット補正前の値で比較）

**タイムスタンプ補正:**
- 各チャンクのセグメントに `chunkOffset`（秒）を加算
- `chunkOffset = max(0, chunkIndex × 300 - 30)`（オーバーラップ考慮）

### 4. WhisperKitTranscriber

**変更:**
- `AudioNormalizer` の呼び出しを削除
- `inferencer.transcribe(samples:sampleRate:modelPath:)` → `inferencer.transcribe(audioURL:modelPath:)` に変更
- それ以外は変更なし

---

## テスト方針

### 削除

- `AudioNormalizerTests.swift`（`AudioNormalizer` 廃止に伴い削除）

### 更新

- `DefaultWhisperInferencerTests.swift` — シグネチャ変更に対応（サンプル配列ではなくWAVファイルを渡す）
- `WhisperKitTranscriberTests.swift` — 同上

### 新規追加

| テストケース | 検証内容 |
|---|---|
| WAV書き込み | 録音後にWAVファイルが存在し、サンプルレート16kHz・モノラルであること |
| チャンク分割: 境界 | 4,800,000サンプルぴったりの音声が1チャンクになること |
| チャンク分割: 複数 | 5分超の音声が複数チャンクに分割されること |
| タイムスタンプ連続性 | チャンク境界をまたぐセグメントのタイムスタンプが単調増加であること |
| 重複除去 | オーバーラップ部分のセグメントが結果に1回だけ含まれること |

---

## 非機能要件

| 指標 | 目標 |
|---|---|
| メモリ使用量（録音中） | ほぼ定数（サンプルバッファ分のみ） |
| メモリ使用量（推論中） | WhisperKitモデル + 約38MB（5分分）以内 |
| ファイルサイズ（1時間） | 約230MB（Float32 WAV）← テキスト比75%削減 |
| インターフェース互換性 | `AudioTranscribing`・`TranscriptOutput` は変更なし |

---

## 変更しないもの

- `AudioTranscribing` プロトコル
- `TranscriptOutput` / `TranscriptSegment` 型
- `WhisperKitTranscriber` の公開インターフェース
- `Orchestrator` / `TranscriptionWorker`
- `SessionAudioArtifactStore`（クリーンアップロジック）
- `MeetingDetector`
