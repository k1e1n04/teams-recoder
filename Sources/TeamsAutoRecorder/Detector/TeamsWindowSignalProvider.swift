import Foundation

public protocol TeamsWindowSignalProviding {
    func isMeetingWindowActive(at: Date) -> Bool
}

public final class TeamsWindowSignalProvider: TeamsWindowSignalProviding {
    private let evaluator: (Date) -> Bool

    public init(evaluator: @escaping (Date) -> Bool) {
        self.evaluator = evaluator
    }

    public func isMeetingWindowActive(at date: Date) -> Bool {
        evaluator(date)
    }
}
