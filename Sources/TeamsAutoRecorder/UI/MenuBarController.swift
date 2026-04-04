import Foundation

public protocol NotificationSink {
    func sendSilent(message: String)
}

public final class MenuBarController {
    private let notificationSink: NotificationSink
    public private(set) var statusText: String = "待機中"

    public init(notificationSink: NotificationSink) {
        self.notificationSink = notificationSink
    }

    public func render(state: AppState) {
        switch state {
        case .idle:
            statusText = "待機中"
        case .recording:
            statusText = "録音中"
            notificationSink.sendSilent(message: "Teams 会議を検知して録音を開始しました")
        case .transcribing:
            statusText = "文字起こし中"
        case .completed:
            statusText = "完了"
        }
    }
}
