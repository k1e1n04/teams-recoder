import Foundation

enum TranscriptionFailureMessageFormatter {
    static func userVisibleMessage(from rawReason: String) -> String {
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            return "不明なエラー"
        }

        // Keep backward compatibility for typo from older builds: modelDonwloadFailed.
        if reason.contains("modelDonwloadFailed") || reason.contains("modelDownloadFailed") {
            return "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。"
        }
        if reason.contains("modelLoadFailed") {
            return "音声認識モデルの読み込みに失敗しました。アプリを再起動してください。"
        }
        if reason.contains("transcriptionFailed") {
            return "文字起こしに失敗しました。もう一度お試しください。"
        }
        return reason
    }
}
