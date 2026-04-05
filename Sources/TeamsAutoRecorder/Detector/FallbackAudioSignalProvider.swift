import Foundation

public final class FallbackAudioSignalProvider: TeamsAudioSignalProviding {
    private let primary: TeamsAudioSignalProviding
    private let fallback: TeamsAudioSignalProviding

    public init(primary: TeamsAudioSignalProviding, fallback: TeamsAudioSignalProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    public func isAudioActive(at date: Date) -> Bool {
        primary.isAudioActive(at: date) || fallback.isAudioActive(at: date)
    }
}
