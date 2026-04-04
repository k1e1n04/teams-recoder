import Foundation
import UserNotifications

extension UNUserNotificationCenter: @unchecked Sendable {}

public protocol NotificationSink {
    func sendSilent(message: String)
}

public protocol UserNotificationCentering: AnyObject, Sendable {
    func authorizationStatus(completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void)
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
}

extension UNUserNotificationCenter: UserNotificationCentering {
    public func authorizationStatus(completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        getNotificationSettings { settings in
            completionHandler(settings.authorizationStatus)
        }
    }
}

public final class MacOSNotificationSink: NotificationSink {
    private let center: UserNotificationCentering

    public init(center: UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public func requestAuthorizationIfNeeded() {
        center.authorizationStatus { [center] status in
            guard status == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in }
        }
    }

    public func sendSilent(message: String) {
        center.authorizationStatus { [center] status in
            switch status {
            case .authorized, .provisional, .ephemeral:
                Self.post(message: message, with: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
                    guard granted else { return }
                    Self.post(message: message, with: center)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func post(message: String, with center: UserNotificationCentering) {
        let content = UNMutableNotificationContent()
        content.title = "Teams Auto Recorder"
        content.body = message
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request, withCompletionHandler: nil)
    }
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
