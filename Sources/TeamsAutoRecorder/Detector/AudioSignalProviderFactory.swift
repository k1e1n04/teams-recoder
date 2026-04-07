import Foundation

public enum AudioSignalProviderFactory {
    public static func make(
        microphoneProvider: TeamsAudioSignalProviding?,
        windowFallbackProvider: TeamsAudioSignalProviding
    ) -> TeamsAudioSignalProviding {
        if let microphoneProvider {
            return FallbackAudioSignalProvider(
                primary: microphoneProvider,
                fallback: windowFallbackProvider
            )
        }
        return windowFallbackProvider
    }
}
