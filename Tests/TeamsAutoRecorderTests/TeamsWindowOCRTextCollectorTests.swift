import XCTest
@testable import TeamsAutoRecorder

final class TeamsWindowOCRTextCollectorTests: XCTestCase {
    func testAcceptsTeamsToolbarWindowOnNonZeroLayer() {
        let info: [String: Any] = [
            kCGWindowOwnerPID as String: 123,
            kCGWindowLayer as String: 24,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: ["Width": 334.0, "Height": 120.0]
        ]

        XCTAssertTrue(
            TeamsWindowOCRTextCollector.shouldProcessWindowInfo(
                info,
                processIDs: [123]
            )
        )
    }
}
