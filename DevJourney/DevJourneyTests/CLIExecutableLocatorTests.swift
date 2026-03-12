import XCTest
@testable import DevJourney

final class CLIExecutableLocatorTests: XCTestCase {

    func testFindExecutableDiscoversHomeLocalBinWithoutPATHEntry() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cli-locator-\(UUID().uuidString)", isDirectory: true)
        let localBin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)

        let claudePath = localBin.appendingPathComponent("claude", isDirectory: false)
        try "#!/bin/sh\nexit 0\n".write(to: claudePath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudePath.path)

        let locator = CLIExecutableLocator(
            fileManager: fileManager,
            environment: [:],
            homeDirectory: root.path
        )

        XCTAssertEqual(locator.findExecutable(named: "claude"), claudePath.path)
        XCTAssertTrue(locator.augmentedEnvironment()["PATH"]?.contains(localBin.path) == true)
    }
}
