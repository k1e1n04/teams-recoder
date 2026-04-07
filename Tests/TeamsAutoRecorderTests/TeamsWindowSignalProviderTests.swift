import XCTest
@testable import TeamsAutoRecorder

final class TeamsWindowSignalProviderTests: XCTestCase {
    func testKeepsMeetingActiveForHoldDurationAfterSignalDrops() {
        var active = true
        let provider = TeamsWindowSignalProvider(holdSeconds: 6) { _ in active }
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(provider.isMeetingWindowActive(at: now))

        active = false
        XCTAssertTrue(provider.isMeetingWindowActive(at: now.addingTimeInterval(3)))
    }

    func testReturnsFalseAfterHoldDurationExpires() {
        var active = true
        let provider = TeamsWindowSignalProvider(holdSeconds: 6) { _ in active }
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(provider.isMeetingWindowActive(at: now))

        active = false
        XCTAssertFalse(provider.isMeetingWindowActive(at: now.addingTimeInterval(7)))
    }
}
