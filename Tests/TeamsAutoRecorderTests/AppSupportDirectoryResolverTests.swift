import XCTest
@testable import TeamsAutoRecorder

final class AppSupportDirectoryResolverTests: XCTestCase {
    func testResolveReturnsTeamsAutoRecorderDirectoryWhenBaseExists() throws {
        let resolver = AppSupportDirectoryResolver(baseDirectoryProvider: {
            URL(fileURLWithPath: "/tmp")
        })

        let resolved = try resolver.resolve()

        XCTAssertEqual(resolved.path, "/tmp/TeamsAutoRecorder")
    }

    func testResolveThrowsWhenBaseDirectoryMissing() {
        let resolver = AppSupportDirectoryResolver(baseDirectoryProvider: {
            nil
        })

        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(error as? AppSupportDirectoryResolverError, .baseDirectoryUnavailable)
        }
    }
}
