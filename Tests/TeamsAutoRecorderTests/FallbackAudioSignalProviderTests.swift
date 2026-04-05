import XCTest
@testable import TeamsAutoRecorder

final class FallbackAudioSignalProviderTests: XCTestCase {
    func testReturnsPrimaryWhenPrimaryIsActive() {
        let provider = FallbackAudioSignalProvider(
            primary: ConstantAudioProvider(value: true),
            fallback: ConstantAudioProvider(value: false)
        )

        XCTAssertTrue(provider.isAudioActive(at: Date()))
    }

    func testReturnsFallbackWhenPrimaryIsInactive() {
        let provider = FallbackAudioSignalProvider(
            primary: ConstantAudioProvider(value: false),
            fallback: ConstantAudioProvider(value: true)
        )

        XCTAssertTrue(provider.isAudioActive(at: Date()))
    }

    func testReturnsFalseWhenBothAreInactive() {
        let provider = FallbackAudioSignalProvider(
            primary: ConstantAudioProvider(value: false),
            fallback: ConstantAudioProvider(value: false)
        )

        XCTAssertFalse(provider.isAudioActive(at: Date()))
    }
}

private struct ConstantAudioProvider: TeamsAudioSignalProviding {
    let value: Bool

    func isAudioActive(at _: Date) -> Bool {
        value
    }
}
