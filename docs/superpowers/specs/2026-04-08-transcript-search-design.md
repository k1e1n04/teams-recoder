# Transcript Full-Text Search Design

## Goal

会議記録（`transcript_text`）とセッション名（`name`）を横断的に検索できる機能を追加する。
`SessionsPanel` のヘッダーに検索バーを設置し、Enter キーまたは検索ボタンで検索を実行する。

## Confirmed Decisions

- 検索対象: `transcript_text` + `name` の両フィールド
- UI 配置: `SessionsPanelHeader` 直下の検索バー（常時表示）
- 検索トリガー: 明示的（Enter キーまたは検索ボタン押下）
- 実装方式: SQLite LIKE クエリ（全セッションを対象）

## Architecture

### 変更コンポーネント

| ファイル | 変更内容 |
|---|---|
| `Storage/SessionRepository.swift` | `searchSessions(query:)` メソッドと `SessionSearching` プロトコルを追加 |
| `App/DashboardViewModel.swift` | 検索状態（`displayedSessions`, `isSearchActive`）と `search(query:)` / `clearSearch()` を追加 |
| `App/Main.swift` | `SessionsPanelHeader` に検索バー、`SessionsPanel` で `displayedSessions` を表示 |

### 新プロトコル

```swift
public protocol SessionSearching {
    func searchSessions(query: String) throws -> [SessionRecord]
}
```

`SessionRepository` が `SessionSearching` に適合する。

## Data Layer

### SQL クエリ

```sql
SELECT session_id, started_at, ended_at, transcript_text,
       failure_stage, failure_reason, name
FROM sessions
WHERE name LIKE ? OR transcript_text LIKE ?
ORDER BY started_at DESC;
```

パラメータには `%{query}%` を束縛する。SQLite のデフォルト照合（ASCII 範囲は case-insensitive）で対応。

### SessionRepository

```swift
extension SessionRepository: SessionSearching {
    public func searchSessions(query: String) throws -> [SessionRecord] {
        let pattern = "%\(query)%"
        let sql = """
        SELECT session_id, started_at, ended_at, transcript_text,
               failure_stage, failure_reason, name
        FROM sessions
        WHERE name LIKE ? OR transcript_text LIKE ?
        ORDER BY started_at DESC;
        """
        let stmt = try database.prepare(sql)
        defer { database.finalize(stmt) }
        bindText(pattern, to: stmt, index: 1)
        bindText(pattern, to: stmt, index: 2)
        var result: [SessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(rowToRecord(stmt))
        }
        return result
    }
}
```

## ViewModel Layer

### 追加状態

```swift
@Published public private(set) var displayedSessions: [SessionRecord] = []
@Published public private(set) var isSearchActive: Bool = false
```

- `sessions`: 通常ロード済みリスト（既存）
- `displayedSessions`: UI に表示するリスト（通常時は `sessions` と同値、検索中は検索結果）

### 追加メソッド

```swift
public func search(query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { clearSearch(); return }
    do {
        displayedSessions = try sessionSearcher?.searchSessions(query: trimmed) ?? []
        isSearchActive = true
        errorMessage = nil
    } catch {
        errorMessage = "検索に失敗しました: \(error)"
    }
}

public func clearSearch() {
    displayedSessions = sessions
    isSearchActive = false
}
```

`loadSessions()` は `displayedSessions = sessions` も更新する（検索していない場合は常に同期）。

### DashboardViewModel イニシャライザ

```swift
private let sessionSearcher: SessionSearching?

public init(
    sessionProvider: SessionListing,
    sessionDeleter: SessionDeleting? = nil,
    sessionRenamer: SessionRenaming? = nil,
    sessionSearcher: SessionSearching? = nil,
    launchAtLoginManager: LaunchAtLoginManaging
)
```

## UI Layer

### SessionsPanelHeader の変更

既存のヘッダー（タイトル + カウンタ）の下に検索バーを追加。

```
会議記録                               [件数]
録音・文字起こし済みセッション
──────────────────────────────────────────
[ 🔍  検索ワードを入力…          [×]  ]
──────────────────────────────────────────
```

- `TextField` + 虫眼鏡アイコン（`Image(systemName: "magnifyingglass")`）
- `.onSubmit` で `viewModel.search(query:)` を呼び出す
- `isSearchActive` が `true` のとき「×」ボタンを表示し、タップで `viewModel.clearSearch()`
- カウンタは `viewModel.displayedSessions.count` を表示

### SessionsPanel の変更

`ForEach` のデータソースを `viewModel.sessions` から `viewModel.displayedSessions` に変更。

検索結果が 0 件のとき:

```
🔍
該当なし
"XXX" に一致するセッションが見つかりません
```

## Error Handling

- `search(query:)` の例外は既存の `viewModel.errorMessage` で表示する（UIの追加変更なし）
- クエリが空白のみの場合は `clearSearch()` を実行し、エラーなし

## Testing

### SessionRepositoryTests（インメモリ DB）

- `name` フィールドでヒットする
- `transcript_text` フィールドでヒットする
- 両フィールドを横断してヒットする
- 0 件のとき空配列を返す
- クエリがワイルドカード文字（`%`, `_`）を含む場合も安全に動作する（エスケープ不要の方針、実用上問題なし）

### DashboardViewModelTests（スタブ）

`SessionSearcherStub` を追加:

```swift
private struct SessionSearcherStub: SessionSearching {
    let results: [SessionRecord]
    let error: Error?

    func searchSessions(query: String) throws -> [SessionRecord] {
        if let error { throw error }
        return results
    }
}
```

テストケース:
- `search(query:)` が `displayedSessions` を検索結果で更新し `isSearchActive = true` になる
- `clearSearch()` が `displayedSessions` を `sessions` に戻し `isSearchActive = false` になる
- 空クエリで `search` を呼ぶと `clearSearch()` と同じ効果
- 検索失敗時に `errorMessage` がセットされる
