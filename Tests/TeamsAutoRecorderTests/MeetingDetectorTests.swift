import XCTest
@testable import TeamsAutoRecorder

final class MeetingDetectorTests: XCTestCase {
    func testStartsWhenWindowThresholdIsMet() {
        let config = MeetingDetectorConfig(startUISeconds: 3, audioWindowSeconds: 4, audioRequiredRatio: 0.75, stopGraceSeconds: 2, minRecordingSeconds: 10, falsePositiveCapPerDay: 2)
        let detector = MeetingDetector(config: config)

        let base = Date(timeIntervalSince1970: 0)
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base))
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(1)))

        // 音声なしでも window が続けば開始する
        let event = detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(2))
        XCTAssertEqual(event, .started(sessionID: "session-2"))
    }

    func testDelaysStopUntilMinimumDuration() {
        let config = MeetingDetectorConfig(startUISeconds: 1, audioWindowSeconds: 1, audioRequiredRatio: 1.0, stopGraceSeconds: 2, minRecordingSeconds: 5, falsePositiveCapPerDay: 2)
        let detector = MeetingDetector(config: config)

        let base = Date(timeIntervalSince1970: 0)
        _ = detector.ingest(windowActive: true, audioActive: true, at: base)

        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(1)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(2)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(4)))

        let stop = detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(5))
        XCTAssertEqual(stop, .stopped(sessionID: "session-0"))
    }

    func testContinuesRecordingWhenWindowLosesFocusButAudioRemains() {
        let config = MeetingDetectorConfig(
            startUISeconds: 1,
            audioWindowSeconds: 4,
            audioRequiredRatio: 0.5,
            stopGraceSeconds: 2,
            minRecordingSeconds: 5,
            falsePositiveCapPerDay: 2
        )
        let detector = MeetingDetector(config: config)
        let base = Date(timeIntervalSince1970: 0)

        _ = detector.ingest(windowActive: true, audioActive: true, at: base)
        // 他のウィンドウにフォーカスしても音声がある限り停止しない
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: true, at: base.addingTimeInterval(1)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: true, at: base.addingTimeInterval(2)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: true, at: base.addingTimeInterval(4)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: true, at: base.addingTimeInterval(10)))
    }

    func testStopsRecordingWhenWindowLosesFocusAndAudioAlsoStops() {
        let config = MeetingDetectorConfig(
            startUISeconds: 1,
            audioWindowSeconds: 4,
            audioRequiredRatio: 0.5,
            stopGraceSeconds: 2,
            minRecordingSeconds: 5,
            falsePositiveCapPerDay: 2
        )
        let detector = MeetingDetector(config: config)
        let base = Date(timeIntervalSince1970: 0)

        _ = detector.ingest(windowActive: true, audioActive: true, at: base)
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(1)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(2)))
        XCTAssertNil(detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(4)))
        let stop = detector.ingest(windowActive: false, audioActive: false, at: base.addingTimeInterval(5))
        XCTAssertEqual(stop, .stopped(sessionID: "session-0"))
    }

    func testContinuesRecordingWhenAudioDropsButWindowRemainsActive() {
        let config = MeetingDetectorConfig(
            startUISeconds: 1,
            audioWindowSeconds: 2,
            audioRequiredRatio: 0.5,
            stopGraceSeconds: 2,
            minRecordingSeconds: 5,
            falsePositiveCapPerDay: 2
        )
        let detector = MeetingDetector(config: config)
        let base = Date(timeIntervalSince1970: 0)

        _ = detector.ingest(windowActive: true, audioActive: true, at: base)
        // 音声が落ちてもウィンドウが開いている間は停止しない
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(1)))
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(2)))
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(4)))
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(5)))
        XCTAssertNil(detector.ingest(windowActive: true, audioActive: false, at: base.addingTimeInterval(10)))
    }
}
