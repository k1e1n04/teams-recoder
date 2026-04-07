import Foundation

public enum TeamsMeetingWindowClassifier {
    private static let requiredKeywords: [String] = [
        "退出",
        "共有",
        "マイク",
        "カメラ"
    ]

    public static func isMeetingWindowTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return requiredKeywords.allSatisfy { keyword in
            trimmed.contains(keyword)
        }
    }
}
