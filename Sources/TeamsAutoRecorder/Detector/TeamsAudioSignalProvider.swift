import Foundation

public protocol TeamsAudioSignalProviding {
    func isAudioActive(at: Date) -> Bool
}

public final class TeamsAudioSignalProvider: TeamsAudioSignalProviding {
    private let evaluator: (Date) -> Bool

    public init(evaluator: @escaping (Date) -> Bool) {
        self.evaluator = evaluator
    }

    public func isAudioActive(at date: Date) -> Bool {
        evaluator(date)
    }
}
