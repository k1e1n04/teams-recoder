#if canImport(ScreenCaptureKit)
import XCTest
@testable import TeamsAutoRecorder

final class RealtimeAudioMixerTests: XCTestCase {
    func testDefaultPlaybackGainIsMutedToAvoidAudioDoubling() {
        let mixer = RealtimeAudioMixer(sampleRate: 16_000)
        XCTAssertEqual(mixer.configuredPlaybackGain, 0)
    }
}
#endif
