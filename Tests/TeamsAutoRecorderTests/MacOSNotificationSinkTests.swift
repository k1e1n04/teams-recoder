import XCTest
import UserNotifications
@testable import TeamsAutoRecorder

final class MacOSNotificationSinkTests: XCTestCase {
    func testSendSilentRequestsAuthorizationThenPostsWhenNotDetermined() {
        let center = NotificationCenterStub(status: .notDetermined, requestGranted: true)
        let sink = MacOSNotificationSink(center: center)

        sink.sendSilent(message: "recording started")

        XCTAssertEqual(center.requestAuthorizationCallCount, 1)
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests.first?.content.body, "recording started")
        XCTAssertNil(center.addedRequests.first?.content.sound)
    }

    func testSendSilentSkipsWhenDenied() {
        let center = NotificationCenterStub(status: .denied, requestGranted: false)
        let sink = MacOSNotificationSink(center: center)

        sink.sendSilent(message: "recording started")

        XCTAssertEqual(center.requestAuthorizationCallCount, 0)
        XCTAssertEqual(center.addedRequests.count, 0)
    }

    func testRequestAuthorizationIfNeededRequestsOnlyWhenNotDetermined() {
        let unknown = NotificationCenterStub(status: .notDetermined, requestGranted: true)
        let denied = NotificationCenterStub(status: .denied, requestGranted: false)

        MacOSNotificationSink(center: unknown).requestAuthorizationIfNeeded()
        MacOSNotificationSink(center: denied).requestAuthorizationIfNeeded()

        XCTAssertEqual(unknown.requestAuthorizationCallCount, 1)
        XCTAssertEqual(denied.requestAuthorizationCallCount, 0)
    }
}

private final class NotificationCenterStub: UserNotificationCentering, @unchecked Sendable {
    private let status: UNAuthorizationStatus
    private let requestGranted: Bool

    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []

    init(status: UNAuthorizationStatus, requestGranted: Bool) {
        self.status = status
        self.requestGranted = requestGranted
    }

    func authorizationStatus(completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        completionHandler(status)
    }

    func requestAuthorization(
        options _: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        requestAuthorizationCallCount += 1
        completionHandler(requestGranted, nil)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
        addedRequests.append(request)
        completionHandler?(nil)
    }
}
