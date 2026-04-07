import XCTest
@testable import TeamsAutoRecorder

final class CompositeWindowSignalProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)

    func testReturnsFalseWhenAllProvidersFalse() {
        let provider = CompositeWindowSignalProvider(providers: [
            TeamsWindowSignalProvider { _ in false },
            TeamsWindowSignalProvider { _ in false }
        ])
        XCTAssertFalse(provider.isMeetingWindowActive(at: now))
    }

    func testReturnsTrueWhenFirstProviderIsTrue() {
        let provider = CompositeWindowSignalProvider(providers: [
            TeamsWindowSignalProvider { _ in true },
            TeamsWindowSignalProvider { _ in false }
        ])
        XCTAssertTrue(provider.isMeetingWindowActive(at: now))
    }

    func testReturnsTrueWhenSecondProviderIsTrue() {
        let provider = CompositeWindowSignalProvider(providers: [
            TeamsWindowSignalProvider { _ in false },
            TeamsWindowSignalProvider { _ in true }
        ])
        XCTAssertTrue(provider.isMeetingWindowActive(at: now))
    }

    func testReturnsTrueWhenAllProvidersTrue() {
        let provider = CompositeWindowSignalProvider(providers: [
            TeamsWindowSignalProvider { _ in true },
            TeamsWindowSignalProvider { _ in true }
        ])
        XCTAssertTrue(provider.isMeetingWindowActive(at: now))
    }

    func testReturnsFalseForEmptyProviders() {
        let provider = CompositeWindowSignalProvider(providers: [])
        XCTAssertFalse(provider.isMeetingWindowActive(at: now))
    }
}
