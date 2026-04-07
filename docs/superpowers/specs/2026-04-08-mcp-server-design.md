# MCP Server Design

**Date:** 2026-04-08  
**Status:** Approved

## Overview

TeamsAutoRecorder.app 内部に MCP (Model Context Protocol) サーバーを内蔵する。アプリ起動時に設定で有効にしていれば自動的に localhost の HTTP/SSE エンドポイントを開き、Claude Code からツール呼び出しで文字起こしデータの取得・日次サマリの登録ができるようにする。

## Goals

- Claude Code が日付を指定してその日の文字起こし一覧を取得できる
- Claude Code が生成した日次サマリをアプリ経由で永続化できる
- MCP サーバーの有効/無効・ポートをアプリ設定で制御できる
- アプリ起動と同時に MCP サーバーが立ち上がる（Claude Code 側でプロセス管理不要）

## Architecture

```
TeamsAutoRecorder.app
  ├── Orchestrator（既存）
  │     └── SessionRepository（既存） ← fetchSessions(for:) を追加
  ├── MCPServer/（新規）
  │     ├── MCPServerController       — 起動/停止, UserDefaults 管理
  │     └── MCPToolHandler            — ツール定義・実行
  └── App/
        └── DashboardViewModel（拡張）— mcpServerEnabled, mcpServerPort
```

トランスポート: **HTTP + SSE** (`modelcontextprotocol/swift-sdk` を使用)  
Claude Code 設定例: `{ "url": "http://localhost:3456/sse" }`

## Components

### MCPServerController

```
protocol MCPServerControlling {
    var isRunning: Bool { get }
    var port: Int { get }
    func start() throws
    func stop()
}
```

- `UserDefaults` に `mcpServerEnabled: Bool`（デフォルト `false`）と `mcpServerPort: Int`（デフォルト `3456`）を保存
- `start()` で `modelcontextprotocol/swift-sdk` の HTTP/SSE サーバーを起動
- `stop()` で graceful shutdown
- `MCPToolHandler` を DI で受け取る

### MCPToolHandler

`SessionRepository` と `SummaryStore`（後述）を DI で受け取り、3 つのツールを実装する。

**`get_transcripts_by_date`**

引数: `date` (String, `"YYYY-MM-DD"` 形式)

処理:
1. 引数を `Date` にパース（ローカルタイムゾーン）
2. `SessionRepository.fetchSessions(for:)` を呼び出す
3. セッション配列を JSON テキストで返す

返却フィールド: `session_id`, `started_at`(ISO8601), `ended_at`(ISO8601), `name`(nullable), `transcript_text`

エラー: 日付パース失敗時は MCP エラーレスポンスを返す。セッションゼロ件は空配列で正常レスポンス。

**`get_daily_summary`**

引数: `date` (String, `"YYYY-MM-DD"` 形式)

処理:
1. `SummaryStore.read(date:)` でファイル読み取り
2. ファイルが存在しない場合は `"No summary for this date."` を返す

**`save_daily_summary`**

引数: `date` (String), `content` (String, Markdown)

処理:
1. `SummaryStore.write(date:content:)` でファイル書き込み
2. 成功時は `"Summary saved."` を返す

### SummaryStore

```
struct SummaryStore {
    let directory: URL  // ~/Library/Application Support/TeamsAutoRecorder/summaries/
    func read(date: String) throws -> String?
    func write(date: String, content: String) throws
}
```

- ファイルパス: `{directory}/{date}.md`
- `AppSupportDirectoryResolver` でベースディレクトリを解決して初期化時に渡す
- ディレクトリが存在しない場合は `write()` 内で自動作成

### SessionRepository の拡張

```swift
public protocol SessionFetchingByDate {
    func fetchSessions(for date: Date) throws -> [SessionRecord]
}
```

実装: `started_at` が対象日の 00:00:00〜23:59:59（ローカル時刻）に収まるセッションを返す。既存の `rowToRecord` を再利用。

### DashboardViewModel の拡張

`LaunchAtLoginManaging` と同じパターンで `MCPServerControlling` を DI として追加。

```swift
@Published public private(set) var mcpServerEnabled: Bool
@Published public private(set) var mcpServerPort: Int

func setMCPServerEnabled(_ enabled: Bool)
```

トグル ON → `controller.start()`、OFF → `controller.stop()`。起動失敗時は `errorMessage` にセット。

### 設定 UI

既存の設定パネル（ログイン時起動トグルの近く）に追加：

- トグル: **「Claude Code MCP サーバーを有効にする」**
- 有効時のみ表示: ポート番号（編集可）、接続 URL (`http://localhost:{port}/sse`) のコピーボタン
- ポート変更は再起動が必要である旨を注記

## Dependencies

`Package.swift` に追加:

```swift
.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.7.0")
```

ターゲット `TeamsAutoRecorder` の dependencies に `MCP` を追加。

## Data Flow

```
Claude Code
  → HTTP POST /sse  (MCP initialize)
  → HTTP POST /message  (tools/call)
        MCPToolHandler
          → SessionRepository.fetchSessions(for:)
              → SQLite (sessions テーブル, started_at フィルタ)
          ← [SessionRecord]
  ← JSON result
```

## Error Handling

| ケース | 動作 |
|--------|------|
| ポートが使用中 | `start()` が throw、`errorMessage` に表示、サーバーは起動しない |
| 日付フォーマット不正 | MCP ツールエラーレスポンス |
| DB アクセス失敗 | MCP ツールエラーレスポンス |
| サマリディレクトリ作成失敗 | `save_daily_summary` がエラーレスポンス |

## Out of Scope

- 認証・認可（localhost のみのため不要）
- HTTPS 対応
- 複数ポートでの同時起動
- セッションごとのサマリ（日次のみ）
