import Foundation
import ServiceManagement

public protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public enum LaunchAtLoginManagerError: Error {
    case unsupportedStatus
}

public final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        case .notRegistered, .requiresApproval, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
