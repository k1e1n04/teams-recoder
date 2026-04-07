import XCTest
@testable import TeamsAutoRecorder

final class AudioSignalProviderFactoryTests: XCTestCase {
    func testUsesFallbackWhenMicrophoneIsInactive() {
        let provider = AudioSignalProviderFactory.make(
            microphoneProvider: ConstantAudioProvider(value: false),
            windowFallbackProvider: ConstantAudioProvider(value: true)
        )

        XCTAssertTrue(provider.isAudioActive(at: Date()))
    }

    func testUsesWindowFallbackProviderWhenMicrophoneProviderUnavailable() {
        let provider = AudioSignalProviderFactory.make(
            microphoneProvider: nil,
            windowFallbackProvider: ConstantAudioProvider(value: true)
        )

        XCTAssertTrue(provider.isAudioActive(at: Date()))
    }
}

private struct ConstantAudioProvider: TeamsAudioSignalProviding {
    let value: Bool

    func isAudioActive(at _: Date) -> Bool {
        value
    }
}
