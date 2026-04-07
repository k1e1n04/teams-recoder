import Foundation

public enum AppSupportDirectoryResolverError: Error, Equatable {
    case baseDirectoryUnavailable
}

public struct AppSupportDirectoryResolver {
    private let baseDirectoryProvider: () -> URL?

    public init(baseDirectoryProvider: @escaping () -> URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }) {
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    public func resolve() throws -> URL {
        guard let base = baseDirectoryProvider() else {
            throw AppSupportDirectoryResolverError.baseDirectoryUnavailable
        }
        return base.appendingPathComponent("TeamsAutoRecorder", isDirectory: true)
    }
}
