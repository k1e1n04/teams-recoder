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

    func testMapsAudioNormalizationFailedToJapaneseMessage() {
        let raw = #"audioNormalizationFailed("empty or invalid audio content")"#
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "録音データの読み込みに失敗しました。もう一度お試しください。")
    }

    func testMapsSessionSaveFailedToJapaneseMessage() {
        let raw = #"sessionSaveFailed(DatabaseError.executionFailed(message: "disk full"))"#
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "文字起こし結果の保存に失敗しました。空き容量を確認してください。")
    }

    func testFallsBackToRawMessageWhenNoKnownPattern() {
        let raw = "custom-failure"
        let message = TranscriptionFailureMessageFormatter.userVisibleMessage(from: raw)
        XCTAssertEqual(message, "custom-failure")
    }
}
