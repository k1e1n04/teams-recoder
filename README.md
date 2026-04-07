# teams-recoder

Teams 会議を自動検知し、録音停止後に文字起こしを行う macOS 向け MVP の土台実装です。  
現状は Swift Package ベースで、検知・録音・変換・保存・通知の責務分離とテストを先に固めています。

## 現在の実装範囲

- `AppState` によるライフサイクル管理（待機/録音/変換/完了）
- `MeetingDetector` による保守的な開始・停止判定（UI + 音声活動の AND）
- `CaptureEngine` / `AudioMixer` による Teams 音声 + マイク音声の収録フロー
- `TranscriptionWorker` / `WhisperKitTranscriber` による停止後バッチ変換フロー
- `WhisperModelManager` によるモデル永続化と未配置時の自動ダウンロード
- `AudioNormalizer` による 16kHz mono float 正規化
- `Database` / `SessionRepository` による SQLite 保存と `Transcript.txt` / `Transcript.json` 出力
- `DashboardView` / `DashboardViewModel` による保存済み会議一覧表示（開始/終了時刻・文字起こし本文）
- `SystemLaunchAtLoginManager` によるログイン時自動起動トグル
- `MenuBarController` による状態表示とサイレント通知
- `CaptureEngine` による `ScreenCaptureKit` (Teamsアプリ音声) + `AVAudioEngine` (マイク) のライブ収録（利用不可時は従来フォールバック）
- 初回起動時の Screen Recording / Microphone 権限要求と、未許可時の設定画面誘導
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

## 公証

`xcrun notarytool store-credentials` で notary 用の認証情報を Keychain に保存すると、後続の公証で `--keychain-profile` として再利用できます。

```bash
xcrun notarytool store-credentials "teams-auto-recorder-notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOURTEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

以下のように表示されたら登録完了です。

```text
Validating your credentials...
Success. Credentials validated.
Credentials saved to Keychain.
To use them, specify `--keychain-profile "teams-auto-recorder-notary"`
```

このプロファイル名は `notarytool submit` や `scripts/create-dmg.sh --notarize` で使えます。

```bash
xcrun notarytool submit build/TeamsAutoRecorder.dmg \
  --keychain-profile "teams-auto-recorder-notary" \
  --wait

scripts/create-dmg.sh \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize \
  --keychain-profile "teams-auto-recorder-notary"
```

## 仕様・計画

- 設計: `docs/superpowers/specs/2026-04-04-teams-auto-recorder-design.md`
- 実装計画: `docs/superpowers/plans/2026-04-04-teams-auto-recorder-mvp.md`
- 実装計画(WhisperKit基盤): `docs/superpowers/plans/2026-04-05-whisperkit-production-foundation.md`

## 注意点

- `WhisperKitTranscriber` は実 WhisperKit を利用し、初回実行時にモデルを自動取得します。
- モデル保存先は `~/Library/Application Support/TeamsAutoRecorder/Models` です。
- ログイン時自動起動は `ServiceManagement` (`SMAppService.mainApp`) で制御しています。
- 文字起こし前に音声を 16kHz mono float へ正規化します。
- Teams音声の取得は `ScreenCaptureKit` 依存です。権限状態・環境要因で開始できない場合はフォールバック経路で動作します。
