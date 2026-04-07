# Slack Huddle 録音対応 設計書

**日付**: 2026-04-07  
**対象**: teams-recoder (TeamsAutoRecorder)

---

## 概要

Microsoft Teams 会議に加え、Slack Huddle も自動検知して録音・文字起こしを行う機能を追加する。両アプリの検知は同時並行で動作し、どちらかが開始されたタイミングで録音を開始する。

---

## 要件

- Teams 会議と Slack Huddle の両方を自動検知して録音する
- 既存の手動録音ボタンは引き続き機能する
- Slack UI は日本語設定。検知キーワード: `"退出する"`（ハドル離脱ボタン）
- 設定画面や切り替えUIは追加しない（両方常時監視）

---

## アーキテクチャ

### 現状

```
TeamsWindowSignalProvider → RecorderRuntime → MeetingDetector
```

`TeamsWindowSignalProvider` が `hasVisibleTeamsWindow()` を評価し、会議UIが見えているかを1秒ごとに判定する。

### 変更後

```
TeamsWindowSignalProvider ──┐
                             ├─→ CompositeWindowSignalProvider → RecorderRuntime → MeetingDetector
SlackWindowSignalProvider  ──┘
```

`CompositeWindowSignalProvider` は複数の `TeamsWindowSignalProviding` を OR 結合する。Teams または Slack のいずれかで会議UIが検知されれば `windowActive = true` となり、既存の `MeetingDetector` ステートマシンがそのまま録音開始・停止を制御する。

---

## 追加・変更ファイル

### 新規: `Sources/TeamsAutoRecorder/Detector/SlackHuddleWindowClassifier.swift`

`TeamsMeetingWindowClassifier` と同じ構造。Slack Huddle 中のみ表示されるキーワードを保持する。

```swift
public enum SlackHuddleWindowClassifier {
    static let requiredKeywords: [String] = ["退出する"]

    public static func allKeywordsExist(in titles: [String]) -> Bool { ... }
}
```

キーワードが1つだけでも、Slackプロセス（`com.tinyspeck.slackmacgap`）に限定してアクセシビリティAPIを叩くため、Teamsの「退出」との混同は発生しない。

### 新規: `Sources/TeamsAutoRecorder/Detector/CompositeWindowSignalProvider.swift`

複数の `TeamsWindowSignalProviding` を受け取り、いずれか1つが `true` を返せば `true` を返す。

```swift
public final class CompositeWindowSignalProvider: TeamsWindowSignalProviding {
    private let providers: [TeamsWindowSignalProviding]

    public init(providers: [TeamsWindowSignalProviding]) {
        self.providers = providers
    }

    public func isMeetingWindowActive(at date: Date) -> Bool {
        providers.contains { $0.isMeetingWindowActive(at: date) }
    }
}
```

### 変更: `Sources/TeamsAutoRecorder/App/Main.swift`

**`RuntimeController` に追加するメソッド:**

```swift
private func hasVisibleSlackHuddle() -> Bool {
    let bundleID = "com.tinyspeck.slackmacgap"
    let runningApps = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleID)
        .filter { !$0.isTerminated }
    guard !runningApps.isEmpty else { return false }

    guard AXIsProcessTrusted() else { return false }

    let visibleTexts = runningApps.flatMap { app in
        accessibilityTextCollector.collectTexts(for: app.processIdentifier)
    }
    return SlackHuddleWindowClassifier.allKeywordsExist(in: visibleTexts)
}
```

OCRフォールバックは追加しない。Slack HuddleのUIはネイティブコントロールで構成されており、アクセシビリティAPIで十分に取得できると判断する。

**`bootstrapRuntime()` の変更:**

```swift
let teamsWindowProvider = TeamsWindowSignalProvider(holdSeconds: 8, evaluator: { _ in
    self.hasVisibleTeamsWindow()
})
let slackWindowProvider = TeamsWindowSignalProvider(holdSeconds: 8, evaluator: { _ in
    self.hasVisibleSlackHuddle()
})
let windowProvider = CompositeWindowSignalProvider(providers: [teamsWindowProvider, slackWindowProvider])
```

`windowProvider` として `CompositeWindowSignalProvider` を使うように差し替える。既存の `windowFallbackProvider`（音声シグナルプロバイダのフォールバック）も同様に `windowProvider` を参照する。

---

## スコープ外（今回対応しない）

- セッション名・セッションIDへの「Teams」「Slack」種別付与
- OCRフォールバック（Slack Huddle 検知時）
- Slack UI が英語設定の環境への対応
- キーワードの設定UI

---

## テスト方針

- `SlackHuddleWindowClassifier` の単体テスト（既存の `TeamsMeetingWindowClassifier` テストと対称）
- `CompositeWindowSignalProvider` の単体テスト（全false → false、1つでもtrue → true）
- 既存の `TeamsWindowSignalProvider` テストは変更不要
- `RuntimeController` の統合テストは手動確認（Slackを実際に起動してハドルに参加）
