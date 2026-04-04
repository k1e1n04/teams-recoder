import Foundation

public enum PermissionType: String, Equatable {
    case screenRecording
    case microphone
}

public enum PermissionStatus: Equatable {
    case authorized
    case missing([PermissionType])
}

public protocol PermissionChecking: AnyObject {
    func hasScreenRecordingPermission() -> Bool
    func hasMicrophonePermission() -> Bool
    func openSystemSettings()
}

public final class PermissionCoordinator {
    private let checker: PermissionChecking

    public init(checker: PermissionChecking) {
        self.checker = checker
    }

    public func currentStatus() -> PermissionStatus {
        var missing: [PermissionType] = []

        if !checker.hasScreenRecordingPermission() {
            missing.append(.screenRecording)
        }

        if !checker.hasMicrophonePermission() {
            missing.append(.microphone)
        }

        if missing.isEmpty {
            return .authorized
        }

        return .missing(missing)
    }

    public func openSettingsForMissingPermissions() {
        guard case .missing = currentStatus() else {
            return
        }

        checker.openSystemSettings()
    }
}

public final class DefaultPermissionChecker: PermissionChecking {
    public init() {}

    public func hasScreenRecordingPermission() -> Bool {
        true
    }

    public func hasMicrophonePermission() -> Bool {
        true
    }

    public func openSystemSettings() {}
}
