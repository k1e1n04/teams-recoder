import Foundation

public enum TeamsMeetingWindowClassifier {
    static let requiredKeywords: [String] = [
        "退出",
        "共有",
        "マイク",
        "カメラ"
    ]

    public static func allKeywordsExist(in titles: [String]) -> Bool {
        var found = Set<String>()
        for raw in titles {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            for keyword in requiredKeywords where title.contains(keyword) {
                found.insert(keyword)
            }
        }
        return requiredKeywords.allSatisfy(found.contains)
    }
}
