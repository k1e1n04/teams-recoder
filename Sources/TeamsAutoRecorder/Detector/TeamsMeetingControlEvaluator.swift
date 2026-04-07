import Foundation

public enum TeamsMeetingControlEvaluator {
    public static func isMeetingUIActive(
        accessibilityTrusted: Bool,
        visibleTexts: [String]
    ) -> Bool {
        guard accessibilityTrusted else { return false }
        return TeamsMeetingWindowClassifier.allKeywordsExist(in: visibleTexts)
    }
}
