# 設計：要約UI表示 + クリップボードコピー

Date: 2026-04-08

## 概要

MCPツール経由で登録された会議要約をアプリUI上で閲覧できるようにする。また、文字起こしと要約のどちらも1クリックでクリップボードにコピーできるようにする。

## 要件

1. `SessionDetailView`（セッション詳細シート）に要約セクションを追加する
2. 要約がある場合はアンバーアクセント付きカードで上部に表示する
3. 要約がない場合は「要約なし」の点線プレースホルダーを表示する（セクション自体は常に見せる）
4. 要約セクションと文字起こしセクションそれぞれに個別のコピーボタンを配置する
5. 要約がない場合、要約のコピーボタンは非表示にする

## アーキテクチャ

### データフロー

```
SummaryStore（ファイル読み書き: summaries/sessions/{sessionID}.md）
    ↓
DashboardViewModel.readSummary(sessionID:) → String?
    ↓
SessionsPanel（シート表示時に取得）
    ↓
SessionDetailView(summaryText: String?)
```

### 変更ファイル一覧

#### `Sources/TeamsAutoRecorder/App/DashboardViewModel.swift`

- `private let summaryStore: SummaryStore?` プロパティを追加
- `init` に `summaryStore: SummaryStore? = nil` パラメータを追加
- `func readSummary(sessionID: String) -> String?` を追加
  - `try? summaryStore?.readSession(sessionID: sessionID)` を返す
  - 失敗時は nil（エラーは上位に出さない）

#### `Sources/TeamsAutoRecorder/App/Main.swift`（`DashboardFactory`）

- `DashboardFactory.makeViewModel()` で既に生成している `summaryStore` を `DashboardViewModel` に渡す

#### `Sources/TeamsAutoRecorder/App/Main.swift`（`SessionsPanel`）

- `@State private var selectedSummary: String?` を追加
- `.sheet(item: $selectedSession)` のクロージャ内で `viewModel.readSummary(sessionID: session.sessionID)` を呼び、`selectedSummary` にセットする
- `SessionDetailView` の呼び出しに `summaryText: selectedSummary` を追加

#### `Sources/TeamsAutoRecorder/App/Main.swift`（`SessionDetailView`）

- `let summaryText: String?` パラメータを追加（デフォルト `nil`）
- ヘッダー下の Divider 直後に要約セクションを挿入：
  - セクションラベル「要約」（既存 `SectionLabel` スタイル）と「コピー」ボタン（`summaryText != nil` の場合のみ表示）
  - 要約あり: `background #1F2229`、左ボーダー `amber`、テキスト表示
  - 要約なし: 点線ボーダーの枠内に「要約なし」テキスト
  - 要約セクション下に Divider を追加
- 文字起こしセクションのラベル行にコピーボタンを追加
- コピー処理: `NSPasteboard.general.clearContents()` + `setString(_:forType:)` （既存 MCPToggleSection と同じ方法）

## UIコンポーネント詳細

### 要約セクション（あり）

```
[SUMMARY ラベル]                    [⎘ コピー ボタン]
┌─────────────────────────────────────────┐
│ ▌ 要約テキスト（amber left border）      │
└─────────────────────────────────────────┘
```

### 要約セクション（なし）

```
[SUMMARY ラベル]

┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
  要約なし
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
```

### 文字起こしセクション

```
[TRANSCRIPT ラベル]                 [⎘ コピー ボタン]
（文字起こし全文、textSelection enabled）
```

## エッジケース

| 状況 | 挙動 |
|------|------|
| 要約ファイルなし | `readSession` が nil → 「要約なし」プレースホルダー表示、コピーボタン非表示 |
| ファイル読み込みエラー | `try?` で nil 扱い、エラーメッセージは出さない |
| `SummaryStore` が nil（Fallback時）| `readSummary` は nil を返す |
| 文字起こし失敗セッション | 文字起こしコピーボタンは表示する（エラーメッセージ文字列をコピー） |

## テスト対象外

- `SummaryStore` 自体の読み書きは既存実装を流用（変更なし）
- コピー操作後のフィードバック（トースト通知など）は今回スコープ外
