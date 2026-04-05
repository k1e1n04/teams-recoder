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
        openSystemSettings(for: [.screenRecording, .microphone])
    }

    public func openSystemSettings(for permissions: [PermissionType]) {
        let urls = [
            permissions.contains(.screenRecording)
                ? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                : nil,
            permissions.contains(.microphone)
                ? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                : nil
        ].compactMap { $0 }
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    public func requestScreenRecordingPermissionIfNeeded() -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        return CGPreflightScreenCaptureAccess()
    }

    public func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public func requestMicrophonePermission(_ completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}
