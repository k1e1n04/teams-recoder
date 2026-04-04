import XCTest
@testable import TeamsAutoRecorder

final class PermissionCoordinatorTests: XCTestCase {
    func testDetectsMissingPermissionsAndOpensSettings() {
        let checker = MockPermissionChecker(screen: false, mic: true)
        let coordinator = PermissionCoordinator(checker: checker)

        let status = coordinator.currentStatus()
        XCTAssertEqual(status, .missing([.screenRecording]))

        coordinator.openSettingsForMissingPermissions()
        XCTAssertEqual(checker.openSettingsCallCount, 1)
    }
}
