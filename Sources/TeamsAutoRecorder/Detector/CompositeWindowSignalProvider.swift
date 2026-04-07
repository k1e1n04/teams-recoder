import Foundation

public final class CompositeWindowSignalProvider: TeamsWindowSignalProviding {
    private let providers: [TeamsWindowSignalProviding]

    public init(providers: [TeamsWindowSignalProviding]) {
        self.providers = providers
    }

    public func isMeetingWindowActive(at date: Date) -> Bool {
        providers.contains { $0.isMeetingWindowActive(at: date) }
    }
}
