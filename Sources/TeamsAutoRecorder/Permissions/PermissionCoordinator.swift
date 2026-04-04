import Foundation
import AppKit
import AVFoundation
import CoreGraphics

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
        CGPreflightScreenCaptureAccess()
    }

    public func hasMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func openSystemSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        ].compactMap { $0 }
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    public func requestMissingPermissionsIfPossible() -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                semaphore.signal()
            }
            semaphore.wait()
        }
        return hasScreenRecordingPermission() && hasMicrophonePermission()
    }
}
