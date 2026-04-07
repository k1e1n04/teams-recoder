import XCTest
@testable import TeamsAutoRecorder

final class TranscriptionFailureMessageFormatterTests: XCTestCase {
    func testMapsModelDownloadFailedWithTypoToJapaneseMessage() {
        let raw = #"modelLoadFailed("modelDonwloadFailed(\"network\")")"#
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。")
    }

    func testMapsModelDownloadFailedToJapaneseMessage() {
        let raw = #"modelLoadFailed("modelDownloadFailed(\"network\")")"#
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。")
    }

    func testMapsModelLoadFailedToJapaneseMessage() {
        let raw = #"modelLoadFailed("permission denied")"#
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "音声認識モデルの読み込みに失敗しました。アプリを再起動してください。")
    }

    func testFallsBackToRawMessageWhenNoKnownPattern() {
        let raw = "custom-failure"
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "custom-failure")
    }
}
