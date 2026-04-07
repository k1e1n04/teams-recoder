import Foundation

public protocol TeamsWindowSignalProviding {
    func isMeetingWindowActive(at: Date) -> Bool
}

public final class TeamsWindowSignalProvider: TeamsWindowSignalProviding {
    private let evaluator: (Date) -> Bool
    private let holdSeconds: TimeInterval
    private var lastDetectedAt: Date?

    public init(holdSeconds: TimeInterval = 0, evaluator: @escaping (Date) -> Bool) {
        self.holdSeconds = holdSeconds
        self.evaluator = evaluator
    }

    public func isMeetingWindowActive(at date: Date) -> Bool {
        if evaluator(date) {
            lastDetectedAt = date
            return true
        }

        guard holdSeconds > 0, let lastDetectedAt else {
            return false
        }
        return date.timeIntervalSince(lastDetectedAt) <= holdSeconds
    }
}
