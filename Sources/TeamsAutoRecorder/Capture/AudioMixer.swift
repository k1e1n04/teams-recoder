import Foundation

public final class AudioMixer {
    public init() {}

    public func mix(teams: [Float], mic: [Float]) -> [Float] {
        let count = max(teams.count, mic.count)
        guard count > 0 else {
            return []
        }

        return (0..<count).map { index in
            let a = index < teams.count ? teams[index] : 0
            let b = index < mic.count ? mic[index] : 0
            return (a + b) / 2
        }
    }
}
