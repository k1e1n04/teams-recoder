import Foundation

public struct MeetingDetectorConfig: Equatable, Sendable {
    public let startUISeconds: Int
    public let audioWindowSeconds: Int
    public let audioRequiredRatio: Double
    public let stopGraceSeconds: Int
    public let minRecordingSeconds: Int
    public let falsePositiveCapPerDay: Int

    public init(
        startUISeconds: Int = 8,
        audioWindowSeconds: Int = 12,
        audioRequiredRatio: Double = 0.7,
        stopGraceSeconds: Int = 6,
        minRecordingSeconds: Int = 120,
        falsePositiveCapPerDay: Int = 5
    ) {
        self.startUISeconds = startUISeconds
        self.audioWindowSeconds = audioWindowSeconds
        self.audioRequiredRatio = audioRequiredRatio
        self.stopGraceSeconds = stopGraceSeconds
        self.minRecordingSeconds = minRecordingSeconds
        self.falsePositiveCapPerDay = falsePositiveCapPerDay
    }

    public static let forTests = MeetingDetectorConfig(
        startUISeconds: 1,
        audioWindowSeconds: 1,
        audioRequiredRatio: 1,
        stopGraceSeconds: 1,
        minRecordingSeconds: 2,
        falsePositiveCapPerDay: 2
    )
}

public enum MeetingDetectorEvent: Equatable, Sendable {
    case started(sessionID: String)
    case stopped(sessionID: String)
    case fallbackToNotifyOnly
}

public final class MeetingDetector {
    private enum Mode {
        case idle
        case recording(sessionID: String, startedAt: Date)
    }

    private let config: MeetingDetectorConfig
    private var mode: Mode = .idle
    private var uiStreakSeconds = 0
    private var stopStreakSeconds = 0
    private var audioWindow: [Bool] = []
    private var sessionCounter = 0
    private var falsePositivesByDay: [String: Int] = [:]

    public init(config: MeetingDetectorConfig = .init()) {
        self.config = config
    }

    public func ingest(windowActive: Bool, audioActive: Bool, at timestamp: Date) -> MeetingDetectorEvent? {
        if windowActive {
            uiStreakSeconds += 1
        } else {
            uiStreakSeconds = 0
        }

        audioWindow.append(audioActive)
        if audioWindow.count > config.audioWindowSeconds {
            audioWindow.removeFirst(audioWindow.count - config.audioWindowSeconds)
        }

        let currentAudioRatio = Double(audioWindow.filter { $0 }.count) / Double(max(audioWindow.count, 1))

        switch mode {
        case .idle:
            if uiStreakSeconds >= config.startUISeconds && currentAudioRatio >= config.audioRequiredRatio {
                sessionCounter += 1
                let sessionID = "session-\(sessionCounter)"
                mode = .recording(sessionID: sessionID, startedAt: timestamp)
                stopStreakSeconds = 0
                return .started(sessionID: sessionID)
            }
        case let .recording(sessionID, startedAt):
            let shouldStop = !windowActive || currentAudioRatio < config.audioRequiredRatio
            if shouldStop {
                stopStreakSeconds += 1
            } else {
                stopStreakSeconds = 0
            }

            let duration = Int(timestamp.timeIntervalSince(startedAt))
            if stopStreakSeconds >= config.stopGraceSeconds && duration >= config.minRecordingSeconds {
                mode = .idle
                stopStreakSeconds = 0
                uiStreakSeconds = 0
                audioWindow.removeAll(keepingCapacity: true)
                return .stopped(sessionID: sessionID)
            }
        }

        return nil
    }

    public func reportFalsePositive(on date: Date = Date()) -> MeetingDetectorEvent? {
        let key = Self.dayKey(date)
        let nextCount = (falsePositivesByDay[key] ?? 0) + 1
        falsePositivesByDay[key] = nextCount
        if nextCount >= config.falsePositiveCapPerDay {
            return .fallbackToNotifyOnly
        }

        return nil
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
