import XCTest
@testable import DevJourney

final class MCPLaunchServiceTests: XCTestCase {
    @MainActor
    func testStableCommandPathInstallsPersistentAppBundleAndWritesLauncherScript() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceBundleURL = tempRoot
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("DevJourney.app", isDirectory: true)
        let sourceExecutableURL = sourceBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("DevJourney", isDirectory: false)
        let rootDirectoryURL = tempRoot
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("DevJourney", isDirectory: true)
        let installedExecutableURL = rootDirectoryURL
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("DevJourney.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("DevJourney", isDirectory: false)
        let scriptURL = rootDirectoryURL.appendingPathComponent("devjourney-mcp", isDirectory: false)

        try fileManager.createDirectory(
            at: sourceExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "fake-devjourney".write(to: sourceExecutableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceExecutableURL.path)

        let service = MCPLaunchService(
            fileManager: fileManager,
            rootDirectoryProvider: { rootDirectoryURL },
            sourceBundleURLProvider: { sourceBundleURL },
            executablePathProvider: { sourceExecutableURL.path }
        )

        let commandPath = try service.prepareStableCommand()

        XCTAssertEqual(commandPath, scriptURL.path)
        XCTAssertTrue(fileManager.fileExists(atPath: scriptURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: installedExecutableURL.path))

        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("cat | '\(installedExecutableURL.path)' \"$@\" | cat"))
    }
}
