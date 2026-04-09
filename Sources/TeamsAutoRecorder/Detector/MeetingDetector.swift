import Foundation

public struct MeetingDetectorConfig: Equatable, Sendable {
    public let startUISeconds: Int
    public let audioWindowSeconds: Int
    public let audioRequiredRatio: Double
    public let stopGraceSeconds: Int
    public let minRecordingSeconds: Int
    public let falsePositiveCapPerDay: Int
    /// ウィンドウが消えてからこの秒数が経過したら、マイク音声の状態に関わらず強制停止する。
    /// ミーティング終了後に環境音でマイクが拾い続けて録音が終わらない問題を防ぐ。
    public let windowGoneTimeoutSeconds: Int

    public init(
        startUISeconds: Int = 8,
        audioWindowSeconds: Int = 12,
        audioRequiredRatio: Double = 0.7,
        stopGraceSeconds: Int = 6,
        minRecordingSeconds: Int = 120,
        falsePositiveCapPerDay: Int = 5,
        windowGoneTimeoutSeconds: Int = 30
    ) {
        self.startUISeconds = startUISeconds
        self.audioWindowSeconds = audioWindowSeconds
        self.audioRequiredRatio = audioRequiredRatio
        self.stopGraceSeconds = stopGraceSeconds
        self.minRecordingSeconds = minRecordingSeconds
        self.falsePositiveCapPerDay = falsePositiveCapPerDay
        self.windowGoneTimeoutSeconds = windowGoneTimeoutSeconds
    }

    public static let forTests = MeetingDetectorConfig(
        startUISeconds: 1,
        audioWindowSeconds: 1,
        audioRequiredRatio: 1,
        stopGraceSeconds: 1,
        minRecordingSeconds: 2,
        falsePositiveCapPerDay: 2,
        windowGoneTimeoutSeconds: 30
    )
}

public enum MeetingDetectorEvent: Equatable, Sendable {
    case started(sessionID: String)
    case stopped(sessionID: String)
    case transcriptionFailed(sessionID: String, reason: String)
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
    private var windowGoneSeconds = 0
    private var audioWindow: [Bool] = []
    private var falsePositivesByDay: [String: Int] = [:]

    public init(config: MeetingDetectorConfig = .init()) {
        self.config = config
    }

    public func ingest(windowActive: Bool, audioActive: Bool, meetingAppRunning: Bool = true, at timestamp: Date) -> MeetingDetectorEvent? {
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
            if uiStreakSeconds >= config.startUISeconds {
                let sessionID = "session-\(Int(timestamp.timeIntervalSince1970))"
                mode = .recording(sessionID: sessionID, startedAt: timestamp)
                stopStreakSeconds = 0
                return .started(sessionID: sessionID)
            }
        case let .recording(sessionID, startedAt):
            if !windowActive {
                windowGoneSeconds += 1
            } else {
                windowGoneSeconds = 0
            }

            let shouldStop = !windowActive && !audioActive
            if shouldStop {
                stopStreakSeconds += 1
            } else {
                stopStreakSeconds = 0
            }

            let duration = Int(timestamp.timeIntervalSince(startedAt))
            let normalStop = stopStreakSeconds >= config.stopGraceSeconds && duration >= config.minRecordingSeconds
            // Teams/Slack プロセスが終了していて、ウィンドウも消えた状態が続いた場合に強制停止。
            // アプリが起動中は会議中の可能性があるため発動しない（別ウィンドウで作業中の誤停止を防ぐ）。
            let windowGoneStop = !meetingAppRunning && windowGoneSeconds >= config.windowGoneTimeoutSeconds && duration >= config.minRecordingSeconds
            if normalStop || windowGoneStop {
                mode = .idle
                stopStreakSeconds = 0
                windowGoneSeconds = 0
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
